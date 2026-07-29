import 'package:flutter/material.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/pane_drop_geometry.dart';
import 'package:otzaria/widgets/layout/split_pane_content_inset.dart';

/// עובי רצועת המפריד בין שתי חלוניות.
const double kPaneDividerThickness = 12;

/// עובי הקו הנראה בתוך רצועת המפריד במצב מנוחה.
const double _kDividerLineThickness = 1.5;

/// עובי הקו הנראה בהצבעה או בגרירה.
const double _kDividerLineThicknessActive = 4;

/// סכום ה-flex בין שתי חלוניות — קובע את דיוק היחס (0.1%).
const int _kFlexResolution = 1000;

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
  EdgeInsetsGeometry get contentInset => EdgeInsetsDirectional.only(
    start: end && !start ? kPaneDividerThickness : 0,
    end: start && !end ? kPaneDividerThickness : 0,
    top: bottom && !top ? kPaneDividerThickness : 0,
    bottom: top && !bottom ? kPaneDividerThickness : 0,
  );
}

/// מציג את עץ החלוניות של טאב: חלונית בודדת, או פיצולים מקוננים עם
/// מפרידים ניתנים לגרירה.
///
/// [paneBuilder] נקרא לכל חלונית עלה עם הנתיב שלה בעץ. כל עלה נעטף
/// ב-[GlobalObjectKey] לפי זהות האובייקט שלו, כך ששינוי מבנה העץ מעביר
/// את ה-Element שלו (reparenting) במקום להרוס ולבנות אותו מחדש — בלי זה
/// כל פיצול או גרירה היו טוענים מחדש את ה-PDF ומאבדים את מיקום הקריאה.
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
    return _buildNode(root, const [], const _PaneEdges());
  }

  Widget _buildNode(OpenedTab node, PanePath path, _PaneEdges edges) {
    if (node is CombinedTab) {
      return _SplitNode(
        // מפתח לפי זהות הצומת: שינוי מבנה מחליף את הצומת ומאפס נכון את
        // היחס המקומי, בעוד גרירת מפריד משנה אותו במקום ולא נוגעת במפתח.
        key: ObjectKey(node),
        node: node,
        path: path,
        edges: edges,
        buildChild: _buildNode,
        onRatioChanged: onRatioChanged,
      );
    }

    return ClipRect(
      child: SplitPaneContentInset(
        contentInset: edges.contentInset,
        child: KeyedSubtree(
          key: GlobalObjectKey(node),
          child: paneBuilder(node, path),
        ),
      ),
    );
  }
}

/// צומת פיצול בודד: שתי חלוניות ומפריד ביניהן.
class _SplitNode extends StatefulWidget {
  final CombinedTab node;
  final PanePath path;
  final _PaneEdges edges;
  final Widget Function(OpenedTab node, PanePath path, _PaneEdges edges)
  buildChild;
  final void Function(PanePath path, double ratio) onRatioChanged;

  const _SplitNode({
    super.key,
    required this.node,
    required this.path,
    required this.edges,
    required this.buildChild,
    required this.onRatioChanged,
  });

  @override
  State<_SplitNode> createState() => _SplitNodeState();
}

class _SplitNodeState extends State<_SplitNode> {
  late double _ratio;
  bool _dragging = false;

  bool get _isVertical => widget.node.axis == SplitAxis.vertical;

  @override
  void initState() {
    super.initState();
    _ratio = widget.node.splitRatio;
  }

  @override
  void didUpdateWidget(_SplitNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    // מסתנכרן עם יחס שהגיע מבחוץ (איפוס מתפריט, טעינה מדיסק). ההשוואה לערך
    // ולא לזהות: המפתח מבטיח שאותו State מקבל תמיד את אותו צומת.
    if (!_dragging && widget.node.splitRatio != _ratio) {
      _ratio = widget.node.splitRatio;
    }
  }

  /// המקום שנותר לשתי החלוניות אחרי ניכוי המפריד, לפי הגודל בפועל.
  double? get _availableExtent {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final total = _isVertical ? box.size.height : box.size.width;
    final available = total - kPaneDividerThickness;
    return available > 0 ? available : null;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final availableExtent = _availableExtent;
    if (availableExtent == null) return;
    // ב-RTL הציר האופקי הפוך: גרירה שמאלה מגדילה את החלונית הראשונה.
    final delta = _isVertical
        ? details.delta.dy
        : (Directionality.of(context) == TextDirection.rtl
              ? -details.delta.dx
              : details.delta.dx);

    // ההגבלה בפיקסלים ולא באחוזים — בחלונית מקוננת צרה יחס קבוע היה
    // מאפשר לכווץ חלונית עד לרוחב בלתי שמיש.
    final minRatio = (kMinPaneExtent / availableExtent).clamp(0.0, 0.5);
    setState(() {
      _ratio = (_ratio + delta / availableExtent).clamp(minRatio, 1 - minRatio);
    });
  }

  void _commit() {
    _dragging = false;
    widget.node.splitRatio = _ratio;
    widget.onRatioChanged(widget.path, _ratio);
  }

  void _resetRatio() {
    setState(() => _ratio = 0.5);
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    // חלוקה ב-flex ולא ב-LayoutBuilder: בנייה בזמן layout בונה מחדש את כל
    // תת-העץ בכל שינוי גודל, והופכת מפתח כפול ל-assertion חסר פשר.
    final firstFlex = (_ratio * _kFlexResolution).round().clamp(
      1,
      _kFlexResolution - 1,
    );

    // כל חלונית יורשת את גבולות ההורה, ומקבלת גבול נוסף בצד שבו
    // המפריד החדש נוגע בה.
    final firstEdges = _isVertical
        ? widget.edges.copyWith(bottom: true)
        : widget.edges.copyWith(end: true);
    final secondEdges = _isVertical
        ? widget.edges.copyWith(top: true)
        : widget.edges.copyWith(start: true);

    final children = <Widget>[
      Expanded(
        flex: firstFlex,
        child: widget.buildChild(
          widget.node.rightTab,
          [...widget.path, kFirstPane],
          firstEdges,
        ),
      ),
      _PaneDivider(
        isVertical: _isVertical,
        onDragStart: () => _dragging = true,
        onDragUpdate: _onDragUpdate,
        onDragEnd: _commit,
        onReset: _resetRatio,
      ),
      Expanded(
        flex: _kFlexResolution - firstFlex,
        child: widget.buildChild(
          widget.node.leftTab,
          [...widget.path, kSecondPane],
          secondEdges,
        ),
      ),
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
  }
}

/// רצועת המפריד: אזור התפיסה רחב מהקו הנראה, כדי שתפיסה בעכבר תהיה נוחה
/// בלי לעבות את החזות.
///
/// מצב ההדגשה נשמר כאן ולא בצומת: `setState` בצומת בונה מחדש את שתי חלוניות
/// הקריאה, וריחוף עכבר על המפריד היה מרנדר מחדש שני ספרים.
class _PaneDivider extends StatefulWidget {
  final bool isVertical;
  final VoidCallback onDragStart;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;

  const _PaneDivider({
    required this.isVertical,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onReset,
  });

  @override
  State<_PaneDivider> createState() => _PaneDividerState();
}

class _PaneDividerState extends State<_PaneDivider> {
  bool _hovering = false;
  bool _dragging = false;

  bool get isVertical => widget.isVertical;

  void _setDragging(bool value) {
    if (_dragging != value) setState(() => _dragging = value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = _hovering || _dragging;
    final lineThickness = active
        ? _kDividerLineThicknessActive
        : _kDividerLineThickness;

    void handleDragStart(DragStartDetails _) {
      _setDragging(true);
      widget.onDragStart();
    }

    void handleDragEnd(DragEndDetails _) {
      _setDragging(false);
      widget.onDragEnd();
    }

    return MouseRegion(
      cursor: isVertical
          ? SystemMouseCursors.resizeRow
          : SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onReset,
        onHorizontalDragStart: isVertical ? null : handleDragStart,
        onHorizontalDragUpdate: isVertical ? null : widget.onDragUpdate,
        onHorizontalDragEnd: isVertical ? null : handleDragEnd,
        onVerticalDragStart: isVertical ? handleDragStart : null,
        onVerticalDragUpdate: isVertical ? widget.onDragUpdate : null,
        onVerticalDragEnd: isVertical ? handleDragEnd : null,
        child: Semantics(
          container: true,
          label: isVertical
              ? 'מפריד בין חלוניות — גרירה למעלה ולמטה'
              : 'מפריד בין חלוניות — גרירה לצדדים',
          child: SizedBox(
            width: isVertical ? null : kPaneDividerThickness,
            height: isVertical ? kPaneDividerThickness : null,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                width: isVertical ? double.infinity : lineThickness,
                height: isVertical ? lineThickness : double.infinity,
                decoration: BoxDecoration(
                  color: active
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(lineThickness / 2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
