import 'package:flutter/material.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/tabs/models/pane_group_tab.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/resolving_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/view/pane_tab_strip.dart';
import 'package:otzaria/tabs/view/pane_tabs_scope.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// גובה שורת הכרטיסיות העצמאית — רק לכרטיסיות שאין להן סרגל עליון.
const double _kStandaloneStripHeight = 38;

/// האם המסך של [tab] בונה סרגל עליון שיארח את רצועת הכרטיסיות.
///
/// טאב כלי מציג עמוד תוסף או כלי בלי סרגל משלו, וטאב בפענוח הוא מחוון טעינה
/// בלבד; להם נבנית שורת רצועה נפרדת, אחרת לא הייתה דרך להחליף כרטיסייה.
@visibleForTesting
bool paneHostsTabStrip(OpenedTab tab) =>
    tab is! ToolTab && tab is! ResolvingTab;

/// חלונית בטאב: תוכן הכרטיסייה המוצגת, ורצועת כרטיסיות כשיש יותר מאחת.
///
/// כל הכרטיסיות נשארות בעץ הווידג'טים ורק המוצגת מצוירת — מעבר בין כרטיסיות
/// אינו טוען מחדש ספר. [TickerMode] מכבה את הנסתרות, וכך הן גם משחררות תוכן.
///
/// חלונית שאינה קבוצה (טאב שאינו מפוצל) עוברת דרך אותו מבנה בדיוק, בלי
/// רצועה. זה מה שמאפשר לפיצול הראשון לשמר את מיקום הקריאה: ה-
/// [GlobalObjectKey] של הכרטיסייה נשאר על אותו סוג ילד לפני ואחרי.
class PaneView extends StatefulWidget {
  /// החלונית — [PaneGroupTab] או כרטיסייה בודדת.
  final OpenedTab pane;

  /// נתיב החלונית בעץ הפיצולים של הטאב.
  final PanePath path;

  /// בונה את תוכן הכרטיסייה.
  final Widget Function(OpenedTab tab) contentBuilder;

  const PaneView({
    super.key,
    required this.pane,
    required this.path,
    required this.contentBuilder,
  });

  @override
  State<PaneView> createState() => _PaneViewState();
}

class _PaneViewState extends State<PaneView> {
  /// הכרטיסייה שהוצגה בבנייה הקודמת. החלונית משתנה במקום, ולכן אי-אפשר
  /// להשוות מול הווידג'ט הישן — הוא אותו אובייקט.
  OpenedTab? _lastShown;

  List<OpenedTab> get _tabs {
    final group = widget.pane;
    return group is PaneGroupTab ? group.tabs : [group];
  }

  int get _activeIndex {
    final group = widget.pane;
    return group is PaneGroupTab ? group.activeIndex : 0;
  }

  /// מעביר את פוקוס המקלדת לספר שהוצג זה עתה, כדי שגלילה בחיצים תמשיך בו.
  /// בבנייה הראשונה אין העברה — היא הייתה גונבת פוקוס בעליית המסך.
  void _syncFocusToShownTab(OpenedTab shown) {
    final previous = _lastShown;
    _lastShown = shown;
    if (previous == null || identical(previous, shown)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusRepository().requestTabContentFocus(shown);
    });
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.pane;
    final strip = group is PaneGroupTab
        ? PaneTabStrip(pane: group, path: widget.path)
        : null;
    final tabs = _tabs;
    final activeIndex = _activeIndex;
    final hostsStrip = paneHostsTabStrip(tabs[activeIndex]);
    _syncFocusToShownTab(tabs[activeIndex]);

    final content = IndexedStack(
      index: activeIndex,
      sizing: StackFit.expand,
      children: [
        for (var i = 0; i < tabs.length; i++)
          KeyedSubtree(
            // מפתח גלובלי לפי זהות הכרטיסייה: פיצול, גרירה לחלונית אחרת או
            // סגירת אחות מעבירים את ה-Element במקום לבנות אותו מחדש ולאבד
            // את מיקום הקריאה.
            key: GlobalObjectKey(tabs[i]),
            child: TickerMode(
              enabled: i == activeIndex,
              child: PaneTabsScope(
                // רק הכרטיסייה המוצגת מקבלת את הרצועה; הנסתרות היו בונות
                // עותקים שלה שאיש אינו רואה.
                strip: i == activeIndex && hostsStrip ? strip : null,
                child: widget.contentBuilder(tabs[i]),
              ),
            ),
          ),
      ],
    );

    if (strip == null || hostsStrip) return content;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: AppSurfaces.topBarBackground(context),
          child: SizedBox(
            height: _kStandaloneStripHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: strip,
              ),
            ),
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}
