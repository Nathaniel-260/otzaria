import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pane_group_tab.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/view/pane_drop_target.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// רוחב מרבי לכרטיסייה ברצועת החלונית.
const double kPaneTabMaxWidth = 168;

/// רוחב מזערי — מתחתיו הכותרת אינה קריאה ועדיף לגלול.
const double kPaneTabMinWidth = 84;

const double _kChipHeight = 30;
const double _kChipRadius = 8;
const double _kInsertLineWidth = 3;

/// רצועת הכרטיסיות של חלונית בטאב מפוצל.
///
/// יושבת במקום הכותרת בסרגל העליון של החלונית (ראו [PaneTabsScope]), ולכן
/// אינה מוסיפה שורה לתצוגה: הכרטיסייה המוצגת *היא* הכותרת.
class PaneTabStrip extends StatefulWidget {
  /// החלונית שאת כרטיסיותיה הרצועה מציגה.
  final PaneGroupTab pane;

  /// נתיב החלונית בעץ הפיצולים — מזהה את מקור הגרירה ואת יעד ההפלה.
  final PanePath path;

  const PaneTabStrip({
    super.key,
    required this.pane,
    required this.path,
  });

  @override
  State<PaneTabStrip> createState() => _PaneTabStripState();
}

class _PaneTabStripState extends State<PaneTabStrip> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _rowKey = GlobalKey();

  /// מיקום ההכנסה בגרירה מעל הרצועה, או `null` כשאין גרירה.
  int? _insertIndex;

  List<OpenedTab> get _tabs => widget.pane.tabs;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isRtl => Directionality.of(context) == TextDirection.rtl;

  /// רוחב אחיד לכל הכרטיסיות, כך שכולן ייכנסו כשיש מקום.
  double _chipWidth(double available) {
    if (_tabs.isEmpty) return kPaneTabMaxWidth;
    final ideal = available / _tabs.length;
    return ideal.clamp(kPaneTabMinWidth, kPaneTabMaxWidth);
  }

  int _insertIndexFor(double localDx, double chipWidth) {
    final total = chipWidth * _tabs.length;
    final flowX = _isRtl ? total - localDx : localDx;
    for (var i = 0; i < _tabs.length; i++) {
      if (flowX < chipWidth * i + chipWidth / 2) return i;
    }
    return _tabs.length;
  }

  void _updateInsertIndex(Offset globalOffset, double chipWidth) {
    final box = _rowKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final next = _insertIndexFor(box.globalToLocal(globalOffset).dx, chipWidth);
    if (next != _insertIndex) setState(() => _insertIndex = next);
  }

  void _clearInsertIndex() {
    if (_insertIndex != null) setState(() => _insertIndex = null);
  }

  /// הרצועה מקבלת כל כרטיסייה שאינה כבר במקומה המדויק.
  bool _accepts(PaneDragData data) =>
      !_samePath(data.sourcePath, widget.path) || _tabs.length > 1;

  static bool _samePath(PanePath? a, PanePath? b) {
    if (a == null || b == null) return a == null && b == null;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _completeDrop(PaneDragData data) {
    final insertIndex = _insertIndex;
    _clearInsertIndex();
    if (insertIndex == null) return;

    final bloc = context.read<TabsBloc>();
    if (_samePath(data.sourcePath, widget.path)) {
      final oldIndex = _tabs.indexWhere((t) => identical(t, data.tab));
      if (oldIndex == -1) return;
      // תיאום לקונבנציית הסרה-ואז-הכנסה: אחרי הסרת הכרטיסייה כל מיקום
      // שאחריה נסוג באחד.
      final target = insertIndex > oldIndex ? insertIndex - 1 : insertIndex;
      bloc.add(ReorderPaneTab(data.tab, target));
      return;
    }

    bloc.add(
      DropTabOnPane(
        tab: data.tab,
        targetPath: widget.path,
        position: PaneDropPosition.center,
        sourcePath: data.sourcePath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // מקום לכפתור ההוספה נשמר תמיד, אחרת הוא נדחק החוצה בחלונית צרה.
        final available = (constraints.maxWidth - _kChipHeight).clamp(
          0.0,
          double.infinity,
        );
        final chipWidth = _chipWidth(available);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: DragTarget<PaneDragData>(
                onWillAcceptWithDetails: (details) {
                  if (!_accepts(details.data)) return false;
                  _updateInsertIndex(details.offset, chipWidth);
                  return true;
                },
                onMove: (details) {
                  if (_accepts(details.data)) {
                    _updateInsertIndex(details.offset, chipWidth);
                  }
                },
                onLeave: (_) => _clearInsertIndex(),
                onAcceptWithDetails: (details) => _completeDrop(details.data),
                builder: (context, _, _) => SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  child: Stack(
                    children: [
                      Row(
                        key: _rowKey,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < _tabs.length; i++)
                            _PaneTabChip(
                              key: ObjectKey(_tabs[i]),
                              tab: _tabs[i],
                              path: widget.path,
                              width: chipWidth,
                              isSelected: i == widget.pane.activeIndex,
                              onDragFinished: _clearInsertIndex,
                            ),
                        ],
                      ),
                      if (_insertIndex != null)
                        _InsertIndicator(
                          left: _insertLineLeft(_insertIndex!, chipWidth),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            _AddTabButton(path: widget.path),
          ],
        );
      },
    );
  }

  /// הקצה השמאלי של קו החיווי, מוגבל לגבולות השורה כדי שלא ייחתך ב-Stack.
  double _insertLineLeft(int index, double chipWidth) {
    final total = chipWidth * _tabs.length;
    final accumulated = chipWidth * index;
    final edge = _isRtl ? total - accumulated : accumulated;
    final maxLeft = total - _kInsertLineWidth;
    if (maxLeft <= 0) return 0;
    return (edge - _kInsertLineWidth / 2).clamp(0.0, maxLeft);
  }
}

/// כותרת חיה של הכרטיסייה, כשהיא משתנה בזמן ריצה (שאילתת חיפוש).
ValueListenable<String>? _liveTitleOf(OpenedTab tab) =>
    tab is SearchingTab ? tab.titleNotifier : null;

/// מיקום הקריאה הנוכחי בכרטיסייה — "פרק ג" וכדומה.
ValueListenable<String>? _liveLocationOf(OpenedTab tab) => switch (tab) {
  TextBookTab() => tab.currentTitle,
  PdfBookTab() => tab.currentTitle,
  PdfCommentatorsTab() => tab.sourceTab.currentTitle,
  _ => null,
};

/// תווית הכרטיסייה: שם הספר, ובמוצגת גם מיקום הקריאה.
///
/// המיקום היה עד כה בכותרת הסרגל, שהרצועה תפסה את מקומה; בלעדיו לא היה
/// בתצוגה המפוצלת שום חיווי לאיפה בספר אנחנו.
class _ChipLabel extends StatelessWidget {
  final OpenedTab tab;
  final bool isSelected;
  final TextStyle style;

  const _ChipLabel({
    required this.tab,
    required this.isSelected,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final liveTitle = _liveTitleOf(tab);
    if (liveTitle != null) {
      return ValueListenableBuilder<String>(
        valueListenable: liveTitle,
        builder: (context, title, _) => _text(context, title),
      );
    }

    final location = isSelected ? _liveLocationOf(tab) : null;
    if (location == null) return _text(context, tab.title);

    return ValueListenableBuilder<String>(
      valueListenable: location,
      builder: (context, value, _) =>
          _text(context, tab.title, location: value),
    );
  }

  Widget _text(BuildContext context, String title, {String location = ''}) {
    final cs = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        text: title,
        children: location.isEmpty
            ? null
            : [
                TextSpan(
                  text: '  $location',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// כרטיסייה בודדת ברצועה.
class _PaneTabChip extends StatefulWidget {
  final OpenedTab tab;
  final PanePath path;
  final double width;
  final bool isSelected;
  final VoidCallback onDragFinished;

  const _PaneTabChip({
    super.key,
    required this.tab,
    required this.path,
    required this.width,
    required this.isSelected,
    required this.onDragFinished,
  });

  @override
  State<_PaneTabChip> createState() => _PaneTabChipState();
}

class _PaneTabChipState extends State<_PaneTabChip> {
  bool _hovering = false;

  void _select() => context.read<TabsBloc>().add(ShowPaneTab(widget.tab));

  void _close() => context.read<TabsBloc>().add(ClosePaneTab(widget.tab));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showClose = widget.isSelected || _hovering;

    final content = Container(
      width: widget.width,
      height: _kChipHeight,
      padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
      decoration: BoxDecoration(
        color: AppSurfaces.paneTabChip(
          cs,
          isSelected: widget.isSelected,
          isHovered: _hovering,
        ),
        borderRadius: BorderRadius.circular(_kChipRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ChipLabel(
              tab: widget.tab,
              isSelected: widget.isSelected,
              style: TextStyle(
                fontSize: 13,
                fontWeight: widget.isSelected
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: widget.isSelected ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ),
          // מקום ה-X שמור תמיד: הופעתו בהצבעה הייתה מקצרת את הכותרת ומזיזה
          // את הטקסט תחת הסמן.
          SizedBox(
            width: 22,
            child: showClose
                ? IconButton(
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                    ),
                    constraints: const BoxConstraints.tightFor(
                      width: 22,
                      height: 22,
                    ),
                    tooltip: 'סגור כרטיסייה',
                    onPressed: _close,
                    icon: const Icon(FluentIcons.dismiss_24_regular, size: 12),
                  )
                : null,
          ),
        ],
      ),
    );

    final data = PaneDragData(tab: widget.tab, sourcePath: widget.path);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Listener(
        // בחירה על pointer-down כדי שגרירה מיידית לא תבלע את הלחיצה; לחצן
        // אמצעי סוגר, כמו בדפדפן.
        onPointerDown: (event) {
          if (event.buttons == kMiddleMouseButton) {
            _close();
            return;
          }
          if (event.buttons == kPrimaryMouseButton && !widget.isSelected) {
            _select();
          }
        },
        child: Tooltip(
          message: widget.tab.title,
          waitDuration: const Duration(milliseconds: 600),
          child: Draggable<PaneDragData>(
            data: data,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: _ChipDragFeedback(width: widget.width, child: content),
            childWhenDragging: Opacity(opacity: 0.35, child: content),
            onDragEnd: (_) => widget.onDragFinished(),
            onDraggableCanceled: (_, _) => widget.onDragFinished(),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// הכרטיסייה הצפה תחת הסמן. מוצגת ב-[Overlay] ולכן אינה יורשת ערכת נושא.
class _ChipDragFeedback extends StatelessWidget {
  final double width;
  final Widget child;

  const _ChipDragFeedback({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: Directionality.of(context),
      child: Theme(
        data: theme,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: Material(
            color: theme.colorScheme.surfaceContainerHigh,
            elevation: 8,
            borderRadius: BorderRadius.circular(_kChipRadius),
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );
  }
}

/// קו אנכי המסמן היכן הכרטיסייה הנגררת תיכנס.
class _InsertIndicator extends StatelessWidget {
  final double left;

  const _InsertIndicator({required this.left});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 3,
      bottom: 3,
      left: left,
      width: _kInsertLineWidth,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(_kInsertLineWidth / 2),
          ),
        ),
      ),
    );
  }
}

/// מביא לחלונית כרטיסייה שכבר פתוחה בשורה הראשית.
///
/// ספר חדש נפתח תמיד כטאב עליון, ולכן זו הדרך להוסיף כרטיסייה לחלונית בלי
/// גרירה — במקלדת ובמסך מגע.
class _AddTabButton extends StatelessWidget {
  final PanePath path;

  const _AddTabButton({required this.path});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (previous, current) => previous.tabs != current.tabs,
      builder: (context, state) {
        final candidates = [
          for (final tab in state.tabs)
            if (!identical(tab, state.currentTab)) tab,
        ];
        if (candidates.isEmpty) return const SizedBox.shrink();

        return MenuAnchor(
          menuChildren: [
            for (final tab in candidates)
              MenuItemButton(
                onPressed: () => context.read<TabsBloc>().add(
                  DropTabOnPane(
                    tab: tab,
                    targetPath: path,
                    position: PaneDropPosition.center,
                  ),
                ),
                child: Text(tab.title),
              ),
          ],
          builder: (context, controller, _) => IconButton(
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
            ),
            constraints: const BoxConstraints.tightFor(
              width: _kChipHeight,
              height: _kChipHeight,
            ),
            tooltip: 'הבא כרטיסייה לחלונית זו',
            icon: const Icon(FluentIcons.add_24_regular, size: 16),
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
          ),
        );
      },
    );
  }
}
