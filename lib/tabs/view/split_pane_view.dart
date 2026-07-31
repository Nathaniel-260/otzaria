import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/pane_drop_geometry.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/split_pane_content_inset.dart';

/// עובי רצועת המפריד בעכבר.
const double kPaneDividerThickness = 12;

/// עובי רצועת המפריד במגע — אצבע אינה מדייקת ל-12 פיקסלים.
const double kPaneDividerThicknessTouch = 24;

/// עובי ידית המפריד כשהיא מוצגת. במנוחה אין ידית כלל — הרווח שבין כרטיסי
/// החלוניות הוא ההפרדה.
const double _kDividerHandleThickness = 4;

/// אורך ידית המפריד לאורך הרצועה.
const double _kDividerHandleLength = 40;

/// עיגול פינות כרטיס החלונית.
const double kPaneCardRadius = 10;

/// שוליים סביב כרטיס החלונית, מעבר לרצועת המפריד.
const double kPaneCardMargin = 3;

/// סכום ה-flex בין שתי חלוניות — קובע את דיוק היחס (0.1%).
const int _kFlexResolution = 1000;

/// כמה זז המפריד בכל הקשה על חץ.
const double _kKeyboardNudge = 24;

/// השהיית השמירה אחרי הקשות מקלדת, כדי שהקשה ממושכת תישמר פעם אחת.
const Duration _kKeyboardCommitDelay = Duration(milliseconds: 250);

/// עובי רצועת המפריד לפי אמצעי הקלט של הפלטפורמה.
double paneDividerThicknessFor(TargetPlatform platform) {
  return platform == TargetPlatform.android || platform == TargetPlatform.iOS
      ? kPaneDividerThicknessTouch
      : kPaneDividerThickness;
}

/// באילו צדדים חלונית גובלת במפריד — הבסיס לחישוב שוליי התוכן שלה.
@immutable
class _PaneEdges {
  final bool start;
  final bool end;
  final bool top;
  final bool bottom;

  const _PaneEdges({
    this.start = false,
    this.end = false,
    this.top = false,
    this.bottom = false,
  });

  _PaneEdges copyWith({bool? start, bool? end, bool? top, bool? bottom}) {
    return _PaneEdges(
      start: start ?? this.start,
      end: end ?? this.end,
      top: top ?? this.top,
      bottom: bottom ?? this.bottom,
    );
  }

  /// שוליים המפצים על עובי המפריד בצד הנגדי, כדי שתוכן הקריאה יישאר
  /// מרוכז. חלונית הגובלת במפרידים משני צדי הציר כבר סימטרית ואינה מפוצה.
  EdgeInsetsGeometry contentInset(double thickness) =>
      EdgeInsetsDirectional.only(
        start: end && !start ? thickness : 0,
        end: start && !end ? thickness : 0,
        top: bottom && !top ? thickness : 0,
        bottom: top && !bottom ? thickness : 0,
      );
}

/// מציג את עץ החלוניות של טאב: חלונית בודדת, או פיצולים מקוננים עם
/// מפרידים ניתנים לגרירה.
///
/// [paneBuilder] נקרא לכל חלונית עלה עם הנתיב שלה בעץ.
///
/// שימור מיקום הקריאה בשינוי מבנה הוא באחריות הבונה: עליו לעטוף את תוכן
/// הכרטיסייה ב-[GlobalObjectKey] לפי זהות הכרטיסייה (כפי ש-`PaneView` עושה),
/// כי זהות *החלונית* מתחלפת בפיצול הראשון — ומפתח שמתחלף היה טוען מחדש את
/// ה-PDF. כאן נשמרת רק זהות תיבת הפריסה.
class SplitPaneView extends StatelessWidget {
  /// שורש עץ החלוניות של הטאב.
  final OpenedTab root;

  /// בונה את תוכן חלונית העלה בנתיב הנתון.
  final Widget Function(OpenedTab pane, PanePath path) paneBuilder;

  /// נקרא בתום גרירת מפריד, עם נתיב צומת הפיצול והיחס החדש.
  final void Function(PanePath path, double ratio) onRatioChanged;

  const SplitPaneView({
    super.key,
    required this.root,
    required this.paneBuilder,
    required this.onRatioChanged,
  });

  @override
  Widget build(BuildContext context) {
    final thickness = paneDividerThicknessFor(Theme.of(context).platform);
    final tree = _buildNode(root, const [], const _PaneEdges(), thickness);
    // טאב שאינו מפוצל ממלא את המסך כמו קודם; המסגור נועד להפריד בין חלוניות.
    if (root is! CombinedTab) return tree;
    return ColoredBox(
      color: AppSurfaces.paneGutter(context),
      child: Padding(
        padding: const EdgeInsets.all(kPaneCardMargin),
        child: tree,
      ),
    );
  }

  Widget _buildNode(
    OpenedTab node,
    PanePath path,
    _PaneEdges edges,
    double thickness,
  ) {
    if (node is CombinedTab) {
      return _SplitNode(
        // מפתח לפי זהות הצומת: שינוי מבנה מחליף את הצומת ומאפס נכון את
        // היחס המקומי, בעוד גרירת מפריד משנה אותו במקום ולא נוגעת במפתח.
        key: ObjectKey(node),
        node: node,
        path: path,
        edges: edges,
        thickness: thickness,
        buildChild: _buildNode,
        onRatioChanged: onRatioChanged,
      );
    }

    return ClipRect(
      child: SplitPaneContentInset(
        contentInset: edges.contentInset(thickness),
        child: KeyedSubtree(
          key: ObjectKey(node),
          child: paneBuilder(node, path),
        ),
      ),
    );
  }
}

/// המסגור של חלונית בטאב מפוצל: משטח מעוגל שצף מעל הרווח שבין החלוניות.
/// החלונית הפעילה מסומנת בקו דק — זה החיווי היחיד ל"במה אני עובד".
class PaneCard extends StatelessWidget {
  final bool isActive;
  final Widget child;

  const PaneCard({super.key, required this.isActive, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(kPaneCardRadius);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: AppSurfaces.paneCard(context),
        borderRadius: radius,
        border: Border.all(
          color: AppSurfaces.paneCardBorder(cs, isActive: isActive),
        ),
        boxShadow: [
          BoxShadow(
            color: AppSurfaces.paneCardShadow(cs, isActive: isActive),
            blurRadius: isActive ? 10 : 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      // חיתוך לפי אותו רדיוס: בלעדיו תוכן הספר יוצא מעבר לפינות המעוגלות.
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}

/// צומת פיצול בודד: שתי חלוניות ומפריד ביניהן.
class _SplitNode extends StatefulWidget {
  final CombinedTab node;
  final PanePath path;
  final _PaneEdges edges;
  final double thickness;
  final Widget Function(
    OpenedTab node,
    PanePath path,
    _PaneEdges edges,
    double thickness,
  )
  buildChild;
  final void Function(PanePath path, double ratio) onRatioChanged;

  const _SplitNode({
    super.key,
    required this.node,
    required this.path,
    required this.edges,
    required this.thickness,
    required this.buildChild,
    required this.onRatioChanged,
  });

  @override
  State<_SplitNode> createState() => _SplitNodeState();
}

class _SplitNodeState extends State<_SplitNode> {
  /// היחס מוחזק ב-notifier ולא ב-state: גרירת מפריד מעדכנת רק את ה-Flex,
  /// בעוד `setState` היה בונה מחדש את שתי תצוגות הספרים בכל פריים.
  late final ValueNotifier<double> _ratioNotifier;
  bool _dragging = false;
  Timer? _commitDebounce;

  double get _ratio => _ratioNotifier.value;

  bool get _isVertical => widget.node.axis == SplitAxis.vertical;

  @override
  void initState() {
    super.initState();
    _ratioNotifier = ValueNotifier<double>(widget.node.splitRatio);
  }

  @override
  void dispose() {
    _commitDebounce?.cancel();
    _ratioNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_SplitNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    // מסתנכרן עם יחס שהגיע מבחוץ (איפוס מתפריט, טעינה מדיסק). ההשוואה לערך
    // ולא לזהות: המפתח מבטיח שאותו State מקבל תמיד את אותו צומת.
    if (!_dragging && widget.node.splitRatio != _ratio) {
      _ratioNotifier.value = widget.node.splitRatio;
    }
  }

  /// המקום שנותר לשתי החלוניות אחרי ניכוי המפריד, לפי הגודל בפועל.
  double? get _availableExtent {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final total = _isVertical ? box.size.height : box.size.width;
    final available = total - widget.thickness;
    return available > 0 ? available : null;
  }

  /// מזיז את המפריד ב-[delta] פיקסלים לאורך הציר; חיובי מגדיל את הראשונה.
  void _applyAxisDelta(double delta) {
    final availableExtent = _availableExtent;
    if (availableExtent == null) return;

    // ההגבלה בפיקסלים ולא באחוזים — בחלונית מקוננת צרה יחס קבוע היה
    // מאפשר לכווץ חלונית עד לרוחב בלתי שמיש.
    final minRatio = (kMinPaneExtent / availableExtent).clamp(0.0, 0.5);
    _ratioNotifier.value = (_ratio + delta / availableExtent).clamp(
      minRatio,
      1 - minRatio,
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    // ב-RTL הציר האופקי הפוך: גרירה שמאלה מגדילה את החלונית הראשונה.
    _applyAxisDelta(
      _isVertical
          ? details.delta.dy
          : (Directionality.of(context) == TextDirection.rtl
                ? -details.delta.dx
                : details.delta.dx),
    );
  }

  /// הזזה בהקשה על חץ; [towardFirst] = כיווץ החלונית הראשונה.
  void _nudge({required bool towardFirst}) {
    final before = _ratio;
    _applyAxisDelta(towardFirst ? -_kKeyboardNudge : _kKeyboardNudge);
    // בקצה ה-clamp ההקשה אינה מזיזה דבר, ואין מה לשמור.
    if (_ratio == before) return;
    // הקשה ממושכת מייצרת עשרות אירועים; שמירה בכל אחד מהם הייתה מסרלת את כל
    // עץ הטאבים לדיסק שוב ושוב. הגרירה בעכבר שומרת פעם אחת בסוף — כאן זה
    // מושג בהשהיה קצרה.
    _commitDebounce?.cancel();
    _commitDebounce = Timer(_kKeyboardCommitDelay, _commit);
  }

  /// היחס שיושג בהזזה אחת, לדיווח לקורא מסך. חסום באותם גבולות כמו ההזזה
  /// עצמה, אחרת מוכרז ערך שלא יושג לעולם.
  double _ratioAfterNudge({required bool towardFirst}) {
    final extent = _availableExtent;
    if (extent == null) return _ratio;
    final minRatio = (kMinPaneExtent / extent).clamp(0.0, 0.5);
    final delta = (towardFirst ? -_kKeyboardNudge : _kKeyboardNudge) / extent;
    return (_ratio + delta).clamp(minRatio, 1 - minRatio);
  }

  void _commit() {
    _commitDebounce?.cancel();
    _commitDebounce = null;
    _dragging = false;
    widget.node.splitRatio = _ratio;
    widget.onRatioChanged(widget.path, _ratio);
  }

  void _resetRatio() {
    _ratioNotifier.value = 0.5;
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    // כל חלונית יורשת את גבולות ההורה, ומקבלת גבול נוסף בצד שבו
    // המפריד החדש נוגע בה.
    final firstEdges = _isVertical
        ? widget.edges.copyWith(bottom: true)
        : widget.edges.copyWith(end: true);
    final secondEdges = _isVertical
        ? widget.edges.copyWith(top: true)
        : widget.edges.copyWith(start: true);

    // שתי החלוניות נבנות פעם אחת לכל בנייה של הצומת, ונלכדות ב-closure שלהלן.
    // עדכון היחס מפעיל רק את ה-builder, ו-Flutter מדלג על תת-עץ שהווידג'ט שלו
    // זהה — כך גרירת מפריד אינה בונה מחדש את תצוגות הספרים.
    final firstChild = widget.buildChild(
      widget.node.rightTab,
      [...widget.path, kFirstPane],
      firstEdges,
      widget.thickness,
    );
    final secondChild = widget.buildChild(
      widget.node.leftTab,
      [...widget.path, kSecondPane],
      secondEdges,
      widget.thickness,
    );

    return ValueListenableBuilder<double>(
      valueListenable: _ratioNotifier,
      builder: (context, ratio, _) {
        // חלוקה ב-flex ולא ב-LayoutBuilder: בנייה בזמן layout בונה מחדש את כל
        // תת-העץ בכל שינוי גודל, והופכת מפתח כפול ל-assertion חסר פשר.
        final firstFlex = (ratio * _kFlexResolution).round().clamp(
          1,
          _kFlexResolution - 1,
        );

        final children = <Widget>[
          Expanded(flex: firstFlex, child: firstChild),
          _PaneDivider(
            isVertical: _isVertical,
            thickness: widget.thickness,
            isTouch: widget.thickness == kPaneDividerThicknessTouch,
            ratio: ratio,
            increasedRatio: _ratioAfterNudge(towardFirst: false),
            decreasedRatio: _ratioAfterNudge(towardFirst: true),
            onDragStart: () => _dragging = true,
            onDragUpdate: _onDragUpdate,
            onDragEnd: _commit,
            onReset: _resetRatio,
            onNudge: (towardFirst) => _nudge(towardFirst: towardFirst),
          ),
          Expanded(flex: _kFlexResolution - firstFlex, child: secondChild),
        ];

        return _isVertical
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              );
      },
    );
  }
}

/// רצועת המפריד: אזור התפיסה רחב מהקו הנראה, כדי שתפיסה בעכבר תהיה נוחה
/// בלי לעבות את החזות.
///
/// מצב ההדגשה נשמר כאן ולא בצומת: `setState` בצומת בונה מחדש את שתי חלוניות
/// הקריאה, וריחוף עכבר על המפריד היה מרנדר מחדש שני ספרים.
class _PaneDivider extends StatefulWidget {
  final bool isVertical;

  /// עובי רצועת התפיסה — רחבה יותר במגע.
  final double thickness;

  /// במגע בלבד: לחיצה ארוכה מאפסת. בעכבר היא הייתה חוטפת את הגרירה — מזהה
  /// הלחיצה הארוכה זוכה בזירה ודוחה את מזהי הגרירה.
  final bool isTouch;

  /// היחס הנוכחי, לדיווח לקורא מסך בלבד.
  final double ratio;

  /// היחסים שיושגו בהזזה אחת לכל כיוון — הערכים שקורא מסך יכריז.
  final double increasedRatio;
  final double decreasedRatio;

  final VoidCallback onDragStart;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;

  /// הזזה בהקשה על חץ; `true` = כיווץ החלונית הראשונה.
  final ValueChanged<bool> onNudge;

  const _PaneDivider({
    required this.isVertical,
    required this.thickness,
    required this.isTouch,
    required this.ratio,
    required this.increasedRatio,
    required this.decreasedRatio,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onReset,
    required this.onNudge,
  });

  @override
  State<_PaneDivider> createState() => _PaneDividerState();
}

class _PaneDividerState extends State<_PaneDivider> {
  bool _hovering = false;
  bool _dragging = false;
  bool _focused = false;

  /// node מפורש כדי שההדגשה תשקף פוקוס מקלדת, ושהמפריד יהיה יעד ל-Tab.
  final FocusNode _focusNode = FocusNode(debugLabel: 'מפריד חלוניות');

  bool get isVertical => widget.isVertical;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _setDragging(bool value) {
    if (_dragging != value) setState(() => _dragging = value);
  }

  static String _percent(double ratio) =>
      '${(ratio.clamp(0.0, 1.0) * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = _hovering || _dragging || _focused;

    void handleDragStart(DragStartDetails _) {
      _setDragging(true);
      // אחרי גרירה בעכבר החצים ממשיכים לכוון את אותו מפריד, בלי לחפש אותו
      // מחדש ב-Tab.
      _focusNode.requestFocus();
      widget.onDragStart();
    }

    void handleDragEnd(DragEndDetails _) {
      _setDragging(false);
      widget.onDragEnd();
    }

    // ב-RTL חץ שמאלה מזיז את המפריד שמאלה, כלומר מגדיל את החלונית הראשונה
    // (הימנית) — בדיוק כמו גרירה.
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return MouseRegion(
      cursor: isVertical
          ? SystemMouseCursors.resizeRow
          : SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Focus(
        focusNode: _focusNode,
        // הסמנטיקה מוגדרת במלואה למטה; בלי זה ה-Focus היה מוסיף צומת עוטף
        // ודגלי הפוקוס היו נדבקים לו במקום למחוון עצמו.
        includeSemantics: false,
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          // קיצור עם מקש הצירוף שייך למסך ולא למפריד (למשל Alt+חץ = הקטע הבא).
          final keyboard = HardwareKeyboard.instance;
          if (keyboard.isAltPressed ||
              keyboard.isControlPressed ||
              keyboard.isMetaPressed) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          if (!isVertical) {
            if (key == LogicalKeyboardKey.arrowLeft) {
              widget.onNudge(!isRtl);
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowRight) {
              widget.onNudge(isRtl);
              return KeyEventResult.handled;
            }
          } else {
            if (key == LogicalKeyboardKey.arrowUp) {
              widget.onNudge(true);
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowDown) {
              widget.onNudge(false);
              return KeyEventResult.handled;
            }
          }
          if (key == LogicalKeyboardKey.home) {
            widget.onReset();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: widget.onReset,
          // רק במגע: בעכבר מזהה הלחיצה הארוכה זוכה בזירה ודוחה את הגרירה, כך
          // שהיסוס של חצי שנייה על הרצועה היה מאפס את היחס והורג את הגרירה.
          onLongPress: widget.isTouch ? widget.onReset : null,
          onHorizontalDragStart: isVertical ? null : handleDragStart,
          onHorizontalDragUpdate: isVertical ? null : widget.onDragUpdate,
          onHorizontalDragEnd: isVertical ? null : handleDragEnd,
          onVerticalDragStart: isVertical ? handleDragStart : null,
          onVerticalDragUpdate: isVertical ? widget.onDragUpdate : null,
          onVerticalDragEnd: isVertical ? handleDragEnd : null,
          child: Semantics(
            container: true,
            slider: true,
            focusable: true,
            focused: _focused,
            value: _percent(widget.ratio),
            increasedValue: _percent(widget.increasedRatio),
            decreasedValue: _percent(widget.decreasedRatio),
            label: isVertical
                ? 'מפריד בין חלוניות — גרירה או חצים למעלה ולמטה, Home לאיפוס'
                : 'מפריד בין חלוניות — גרירה או חצים לצדדים, Home לאיפוס',
            onIncrease: () => widget.onNudge(false),
            onDecrease: () => widget.onNudge(true),
            child: SizedBox(
              width: isVertical ? null : widget.thickness,
              height: isVertical ? widget.thickness : null,
              child: Center(
                // ידית קצרה במרכז ולא קו לכל האורך: במנוחה הרווח שבין
                // הכרטיסים הוא ההפרדה, והידית מופיעה רק כשמכוונים אליה.
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  opacity: active ? 1 : 0,
                  child: SizedBox(
                    width: isVertical
                        ? _kDividerHandleLength
                        : _kDividerHandleThickness,
                    height: isVertical
                        ? _kDividerHandleThickness
                        : _kDividerHandleLength,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppSurfaces.paneDividerHandle(
                          colorScheme,
                          isActive: active,
                        ),
                        borderRadius: BorderRadius.circular(
                          _kDividerHandleThickness / 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
