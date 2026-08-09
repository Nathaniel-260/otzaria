import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

/// מחשב כמה כפתורי פעולה ניתן להציג בסרגל הקריאה לפי רוחב המסך.
///
/// מנכה את הרוחב הקבוע של אזור המרכז (כפתורי הניווט + כותרת) והכפתור המוביל,
/// כי ה-AppTopBar מקצה להם את גודלם הטבעי לפני ה-actions. בלי הניכוי הכפתורים
/// היו גולשים במסכים צרים.
int maxToolbarButtonsForWidth(double screenWidth) {
  // center (4 כפתורי ניווט ~168 + כותרת) + leading + ריווחים ≈ 260px קבועים
  const reservedWidth = 260.0;
  const buttonWidth = 44.0; // כפתור ~40 + ריווח
  final available = screenWidth - reservedWidth;
  if (available <= 0) return 0;
  return (available / buttonWidth).floor().clamp(0, 999);
}

/// רכיב שמציג כפתורי פעולה עם יכולת הסתרה במסכים צרים
/// כשחלק מהכפתורים נסתרים, מוצג כפתור "..." שפותח תפריט
///
/// תומך בשני מצבי עבודה:
/// 1. מצב חדש: `actions` + `alwaysInMenu` - כפתורים נעלמים בסדר ההצגה, ותמיד יש תפריט עם כפתורים קבועים
/// 2. מצב ישן: `actions` + `originalOrder` - כפתורים נעלמים לפי עדיפות, תפריט רק אם צריך
class ResponsiveActionBar extends StatefulWidget {
  /// רשימת כפתורי הפעולה.
  /// במצב חדש: סדר ההצגה (מימין לשמאל ב-RTL)
  /// במצב ישן: סדר עדיפות (החשוב ביותר ראשון)
  final List<ActionButtonData> actions;

  /// [מצב חדש] כפתורים שתמיד יהיו בתפריט "..." (גם במסכים רחבים)
  final List<ActionButtonData>? alwaysInMenu;

  /// [מצב ישן] הסדר המקורי של הכפתורים (לתצוגה עקבית)
  final List<ActionButtonData>? originalOrder;

  /// פעולות ניווט שמוצגות כשורת כפתורי אייקון אחת בראש תפריט ה-"..." (עם
  /// tooltip), במקום שורת טקסט נפרדת לכל פעולה. לכל פעולה חייב להיות
  /// [ActionButtonData.icon]. לחיצה משאירה את התפריט פתוח — מעבר קטע נלחץ
  /// שוב ושוב, וסגירה בכל לחיצה הייתה מחייבת פתיחה מחדש בכל קטע.
  final List<ActionButtonData>? menuHeaderActions;

  /// מספר מקסימלי של כפתורים להציג לפני מעבר לתפריט "..."
  final int maxVisibleButtons;

  /// האם כפתור "..." יהיה בצד ימין (ברירת מחדל: false - שמאל)
  final bool overflowOnRight;

  /// היסט מיקום לתפריט ה-"..." ביחס לכפתור.
  final Offset overflowMenuOffset;
  final GlobalKey? overflowButtonKey;
  final bool openOverflowMenu;
  final Map<String, GlobalKey>? menuItemKeysByTooltip;

  const ResponsiveActionBar({
    super.key,
    required this.actions,
    this.alwaysInMenu,
    this.originalOrder,
    this.menuHeaderActions,
    required this.maxVisibleButtons,
    this.overflowOnRight = false,
    this.overflowMenuOffset = const Offset(0, 4),
    this.overflowButtonKey,
    this.openOverflowMenu = false,
    this.menuItemKeysByTooltip,
  }) : assert(
         alwaysInMenu != null || originalOrder != null,
         'Either alwaysInMenu or originalOrder must be provided',
       );

  @override
  State<ResponsiveActionBar> createState() => _ResponsiveActionBarState();
}

class _ResponsiveActionBarState extends State<ResponsiveActionBar> {
  bool _menuOpenRequested = false;

  List<ActionButtonData> get _headerActions =>
      widget.menuHeaderActions ?? const <ActionButtonData>[];

  @override
  void didUpdateWidget(covariant ResponsiveActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.openOverflowMenu) {
      _menuOpenRequested = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // בדיקה אם יש כפתורים בכלל
    final hasAlwaysInMenu =
        widget.alwaysInMenu != null && widget.alwaysInMenu!.isNotEmpty;

    if (widget.actions.isEmpty && !hasAlwaysInMenu && _headerActions.isEmpty) {
      return const SizedBox.shrink();
    }

    // קביעת מצב העבודה
    // New mode is only when originalOrder is NOT provided.
    // If originalOrder is provided, we keep old-mode priority behavior, and
    // allow alwaysInMenu to populate the overflow menu even on wide screens.
    final isNewMode =
        widget.alwaysInMenu != null && widget.originalOrder == null;

    if (isNewMode) {
      return _buildNewMode(context);
    } else {
      return _buildOldMode(context);
    }
  }

  /// מצב חדש: כפתורים נעלמים בסדר ההצגה, תמיד יש תפריט עם כפתורים קבועים
  Widget _buildNewMode(BuildContext context) {
    final totalButtons = widget.actions.length;
    int effectiveMaxVisible = widget.maxVisibleButtons;

    // אם צריך להסתיר רק כפתור אחד, אין טעם להציג תפריט שתופס מקום בעצמו.
    // עדיף פשוט להציג את כל הכפתורים.
    // החרגה: כשהתפריט קיים ממילא (alwaysInMenu או שורת הניווט), הצגת כל
    // הכפתורים תוסיף רוחב ותגרום לגלישה קלה ב-AppBar במסכים צרים.
    if (totalButtons - widget.maxVisibleButtons == 1 &&
        widget.alwaysInMenu!.isEmpty &&
        _headerActions.isEmpty) {
      effectiveMaxVisible = totalButtons;
    }

    List<ActionButtonData> visibleActions;
    List<ActionButtonData> hiddenActions;

    // אם יש מקום לכל הכפתורים, נציג את כולם
    if (effectiveMaxVisible >= totalButtons) {
      visibleActions = List.from(widget.actions);
      hiddenActions = [];
    } else {
      // מסתירים כפתורים מהסוף לתחילה (הימני ביותר יעלם אחרון)
      final numToShow = effectiveMaxVisible;
      visibleActions = widget.actions.take(numToShow).toList();
      hiddenActions = widget.actions.skip(numToShow).toList();
    }

    // תמיד מוסיפים את הכפתורים שצריכים להיות בתפריט
    final allHiddenActions = [...hiddenActions, ...widget.alwaysInMenu!];

    final visibleWidgets = visibleActions
        .map((action) => action.widget)
        .toList();
    final List<Widget> children = [];

    // מסך הספר: תפריט בצד שמאל, כפתורים מימין לשמאל (RTL)
    // תמיד מציגים כפתור "..." אם יש כפתורים בתפריט
    if (allHiddenActions.isNotEmpty || _headerActions.isNotEmpty) {
      children.add(_buildOverflowButton(allHiddenActions));
    }
    // הופכים את הסדר כך שהכפתור הראשון ברשימה (PDF) יהיה ימני ביותר
    children.addAll(visibleWidgets.reversed);

    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      children: children,
    );
  }

  /// מצב ישן: כפתורים נעלמים לפי עדיפות, ותפריט רק אם צריך
  Widget _buildOldMode(BuildContext context) {
    final totalButtons = widget.originalOrder!.length;
    int effectiveMaxVisible = widget.maxVisibleButtons;

    // אם צריך להסתיר רק כפתור אחד, אין טעם להציג תפריט שתופס מקום בעצמו —
    // אלא אם התפריט קיים ממילא בשביל שורת הניווט.
    if (totalButtons - widget.maxVisibleButtons == 1 &&
        _headerActions.isEmpty) {
      effectiveMaxVisible = totalButtons;
    }

    List<ActionButtonData> visibleActions;
    List<ActionButtonData> hiddenActions;

    // אם יש מקום לכל הכפתורים, נציג את כולם וללא תפריט "..."
    if (effectiveMaxVisible >= totalButtons) {
      visibleActions = List.from(widget.originalOrder!);
      hiddenActions = [];
    } else {
      final numToHide = totalButtons - effectiveMaxVisible;

      // ניקח את הכפתורים הפחות חשובים מרשימת העדיפויות
      final Set<ActionButtonData> actionsToHide = widget.actions.reversed
          .take(numToHide)
          .toSet();

      visibleActions = [];
      hiddenActions = [];

      // נחלק את הכפתורים (לפי הסדר המקורי!) לגלויים ונסתרים
      for (final action in widget.originalOrder!) {
        if (actionsToHide.contains(action)) {
          hiddenActions.add(action);
        } else {
          visibleActions.add(action);
        }
      }
    }

    final visibleWidgets = visibleActions
        .map((action) => action.widget)
        .toList();
    final List<Widget> children = [];

    final alwaysInMenu = widget.alwaysInMenu ?? const <ActionButtonData>[];
    final allHiddenActions = [...hiddenActions, ...alwaysInMenu];

    final showOverflow =
        allHiddenActions.isNotEmpty || _headerActions.isNotEmpty;

    if (widget.overflowOnRight) {
      // מסך הספרייה: תפריט בצד ימין. הסדר החזותי R->L דורש היפוך הרשימה.
      children.addAll(visibleWidgets.reversed);
      if (showOverflow) {
        children.add(_buildOverflowButton(allHiddenActions));
      }
    } else {
      // תפריט בצד שמאל
      if (showOverflow) {
        children.add(_buildOverflowButton(allHiddenActions));
      }
      children.addAll(visibleWidgets);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      children: children,
    );
  }

  Widget _buildOverflowButton(List<ActionButtonData> hiddenActions) {
    // יצירת key ייחודי על סמך הכפתורים הנסתרים כדי למנוע בעיות context
    final uniqueKey =
        'overflow_${_headerActions.map((a) => a.tooltip).join('_')}'
        '_${hiddenActions.map((a) => a.tooltip).join('_')}';

    return Builder(
      key: ValueKey(uniqueKey),
      builder: (context) {
        final menuMetrics =
            Theme.of(context).extension<AppMenuMetrics>() ??
            AppMenuMetrics.create(compactMenus: false);
        final menuButton = AppPopupMenuButton<ActionButtonData>(
          key: widget.overflowButtonKey,
          iconData: FluentIcons.more_vertical_24_regular,
          tooltip: 'עוד פעולות',
          position: PopupMenuPosition.under,
          offset: widget.overflowMenuOffset,
          onSelected: (action) {
            action.onPressed?.call();
          },
          itemBuilder: (context) {
            final headerActions = _headerActions;
            final items = <PopupMenuEntry<ActionButtonData>>[];

            if (headerActions.isNotEmpty) {
              items.add(
                AppMenuRowEntry<ActionButtonData>(
                  height: _MenuIconActionRow.rowHeight,
                  child: _MenuIconActionRow(actions: headerActions),
                ),
              );
              if (hiddenActions.isNotEmpty) {
                items.add(
                  PopupMenuDivider(height: menuMetrics.dividerHeight),
                );
              }
            }

            items.addAll(
              hiddenActions.map((action) {
                // אם יש submenuItems, נבנה תת-תפריט
                if (action.submenuItems != null &&
                    action.submenuItems!.isNotEmpty) {
                  final subEntries = action.submenuItems!
                      .map(
                        (subAction) => buildAppPopupMenuItem<ActionButtonData>(
                          context,
                          AppMenuEntry<ActionButtonData>(
                            value: subAction,
                            label: subAction.tooltip ?? '',
                            icon: subAction.icon,
                            enabled: subAction.onPressed != null,
                          ),
                          menuMetrics,
                          null,
                          key: widget
                              .menuItemKeysByTooltip?[subAction.tooltip ?? ''],
                        ),
                      )
                      .toList();
                  return buildAppSubmenuPopupMenuItem<ActionButtonData>(
                    context: context,
                    metrics: menuMetrics,
                    label: action.tooltip ?? '',
                    icon: action.icon,
                    menuChildren: subEntries,
                    onSelected: (subAction) => subAction.onPressed?.call(),
                  );
                }

                // פריט רגיל ללא submenu
                return buildAppPopupMenuItem<ActionButtonData>(
                  context,
                  AppMenuEntry<ActionButtonData>(
                    value: action,
                    label: action.tooltip ?? '',
                    icon: action.icon,
                    enabled: action.onPressed != null,
                  ),
                  menuMetrics,
                  null,
                  key: widget.menuItemKeysByTooltip?[action.tooltip ?? ''],
                );
              }),
            );

            return items;
          },
        );

        if (widget.openOverflowMenu &&
            !_menuOpenRequested &&
            (hiddenActions.isNotEmpty || _headerActions.isNotEmpty)) {
          _menuOpenRequested = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !widget.openOverflowMenu) {
              return;
            }
            final state = widget.overflowButtonKey?.currentState as dynamic;
            state?.showMenu();
          });
        }

        return menuButton;
      },
    );
  }
}

/// שורת כפתורי ניווט אחת בראש תפריט ה-"..." — במקום שורת טקסט לכל פעולה.
/// התפריט נשאר פתוח בלחיצה, ולכן ה-callbacks חייבים לקרוא מצב חי ולא ערך
/// שנקרא בזמן בניית התפריט.
class _MenuIconActionRow extends StatelessWidget {
  final List<ActionButtonData> actions;

  const _MenuIconActionRow({required this.actions});

  static const double _buttonSize = 48;
  static const double _iconSize = 20;

  /// גובה השורה בתפריט — [AppMenuRowEntry] מדווח עליו, ו-showAnchoredAppMenu
  /// מסתמך על סכום הגבהים כדי לבחור כיוון פתיחה.
  static const double rowHeight = _buttonSize + 8;

  @override
  Widget build(BuildContext context) {
    assert(
      actions.every((action) => action.icon != null),
      'menuHeaderActions requires an icon for every action',
    );
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final action in actions)
            IconButton(
              onPressed: action.onPressed,
              tooltip: action.tooltip,
              icon: Icon(action.icon, size: _iconSize),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: _buttonSize,
                minHeight: _buttonSize,
              ),
              style: IconButton.styleFrom(
                // צבע פריט תפריט רגיל, לא הגוון המושתק של כפתור סרגל.
                foregroundColor: colorScheme.onSurface,
                shape: const CircleBorder(),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }
}

/// נתוני כפתור פעולה
class ActionButtonData {
  /// הווידג'ט של הכפתור
  final Widget widget;

  /// האייקון (לשימוש בתפריט הנפתח)
  final IconData? icon;

  /// הטקסט להצגה בתפריט הנפתח
  final String? tooltip;

  /// הפעולה לביצוע כשלוחצים על הכפתור בתפריט
  final VoidCallback? onPressed;

  /// רשימת פריטי תת-תפריט (אם קיימת, זה יהיה submenu)
  final List<ActionButtonData>? submenuItems;

  const ActionButtonData({
    required this.widget,
    this.icon,
    this.tooltip,
    this.onPressed,
    this.submenuItems,
  });

  /// אופן הבנייה של כפתור פשוט.
  static const ActionButtonVisual defaultVisual = ActionButtonVisual.toolbar;

  /// Factory constructor לכפתור פשוט — מונע כפילות של icon/tooltip/onPressed
  /// בין הכפתור עצמו לנתוני התפריט.
  factory ActionButtonData.simple({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required bool compact,
    bool selected = false,
    Key? key,
    ActionButtonVisual visual = defaultVisual,
  }) {
    return ActionButtonData(
      widget: switch (visual) {
        ActionButtonVisual.toolbar => BarButton.icon(
          key: key,
          compact: compact,
          tooltip: tooltip,
          icon: icon,
          selected: selected,
          onPressed: onPressed,
        ),
        ActionButtonVisual.iconButton => IconButton(
          key: key,
          onPressed: onPressed,
          icon: Icon(icon),
          tooltip: tooltip,
        ),
      },
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActionButtonData &&
          runtimeType == other.runtimeType &&
          tooltip == other.tooltip;

  @override
  int get hashCode => tooltip.hashCode;
}

enum ActionButtonVisual {
  toolbar,
  iconButton,
}
