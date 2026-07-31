import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/utils/file/hive_utils.dart';

/// חלונית בטאב מפוצל שמחזיקה כמה כרטיסיות, כמו קבוצת עורכים ב-VS Code.
///
/// מופיעה רק כעלה בתוך [CombinedTab]: הרמה העליונה כבר היא קבוצה — שורת
/// הכרטיסיות של החלון — ולכן קבוצה בשורש הייתה מסתירה כרטיסיות מהמשתמש.
///
/// משתנה במקום (mutable) בכוונה, כמו `splitRatio`: הוספת כרטיסייה שיוצרת
/// אובייקט קבוצה חדש הייתה מחליפה את ה-`GlobalObjectKey` של החלונית ומאתחלת
/// מחדש את כל הספרים שבתוכה.
class PaneGroupTab extends OpenedTab {
  /// הכרטיסיות בסדר התצוגה. לעולם אינה ריקה — קבוצה ריקה מוסרת מהעץ.
  final List<OpenedTab> tabs;

  int _activeIndex;

  PaneGroupTab({
    required List<OpenedTab> tabs,
    int activeIndex = 0,
    bool isPinned = false,
  }) : assert(tabs.isNotEmpty, 'קבוצת חלונית ריקה'),
       tabs = List<OpenedTab>.from(tabs),
       _activeIndex = activeIndex.clamp(0, tabs.length - 1),
       super('', isPinned: isPinned);

  /// עוטפת כרטיסייה בחלונית. צומת פיצול וחלונית קיימת חוזרים כמות שהם, ולכן
  /// אפשר להעביר לכאן כל צומת בעץ בלי לבדוק את טיפוסו.
  static OpenedTab wrap(OpenedTab tab) =>
      tab is PaneGroupTab || tab is CombinedTab
      ? tab
      : PaneGroupTab(tabs: [tab], isPinned: tab.isPinned);

  /// הכרטיסייה המוצגת בחלונית.
  int get activeIndex => _activeIndex;

  set activeIndex(int value) => _activeIndex = value.clamp(0, tabs.length - 1);

  OpenedTab get activeTab => tabs[_activeIndex];

  /// נגזרת מהכרטיסייה המוצגת: כותרת שהוקפאה בבנייה הייתה נשארת מיושנת
  /// ברשימת הטאבים ובחלונות הקפיצה של מערכת ההפעלה.
  @override
  String get title => activeTab.title;

  @override
  set title(String value) =>
      throw UnsupportedError('כותרת חלונית נגזרת מהכרטיסייה שבה');

  /// מוסיפה כרטיסייה והופכת אותה למוצגת. [at] הוא מקום ההכנסה; ברירת המחדל
  /// היא בסוף.
  void addTab(OpenedTab tab, {int? at}) {
    if (tabs.contains(tab)) {
      activeIndex = tabs.indexOf(tab);
      return;
    }
    final index = (at ?? tabs.length).clamp(0, tabs.length);
    tabs.insert(index, tab);
    _activeIndex = index;
  }

  /// מסירה כרטיסייה ומחזירה אם הוסרה. אינה מסירה את האחרונה — קבוצה ריקה
  /// מטופלת בהסרת החלונית כולה מהעץ.
  bool removeTab(OpenedTab tab) {
    if (tabs.length <= 1) return false;
    final index = tabs.indexOf(tab);
    if (index == -1) return false;
    tabs.removeAt(index);
    // אחרי סגירה עוברים לשכנה, כמו בדפדפן: אינדקס שנשאר מעבר לסוף היה
    // מציג את הכרטיסייה האחרונה במקום את זו שליד הנסגרת.
    if (_activeIndex > index || _activeIndex >= tabs.length) {
      _activeIndex = (_activeIndex - 1).clamp(0, tabs.length - 1);
    }
    return true;
  }

  /// מזיזה כרטיסייה קיימת ל-[newIndex] בקונבנציית הסרה-ואז-הכנסה.
  void moveTab(OpenedTab tab, int newIndex) {
    final oldIndex = tabs.indexOf(tab);
    if (oldIndex == -1) return;
    final target = newIndex.clamp(0, tabs.length - 1);
    if (target == oldIndex) return;
    final active = activeTab;
    tabs.removeAt(oldIndex);
    tabs.insert(target, tab);
    _activeIndex = tabs.indexOf(active);
  }

  /// מסמנת כרטיסייה כמוצגת. מחזירה `false` אם אינה בקבוצה.
  bool showTab(OpenedTab tab) {
    final index = tabs.indexOf(tab);
    if (index == -1) return false;
    _activeIndex = index;
    return true;
  }

  @override
  void dispose() {
    for (final tab in tabs) {
      tab.dispose();
    }
    super.dispose();
  }

  factory PaneGroupTab.fromJson(Map<String, dynamic> json) {
    final rawTabs = (json['tabs'] as List?) ?? const [];
    final decoded = <OpenedTab>[];
    for (final raw in rawTabs) {
      try {
        decoded.add(decodePaneChild(castMap(raw)));
      } catch (_) {
        // כרטיסייה מטיפוס לא מוכר (ירידת גרסה) מדולגת, כמו בשורת הכרטיסיות.
      }
    }
    if (decoded.isEmpty) {
      throw const FormatException('קבוצת חלונית בלי כרטיסיות');
    }
    return PaneGroupTab(
      tabs: decoded,
      activeIndex: (json['activeIndex'] as num?)?.toInt() ?? 0,
      isPinned: json['isPinned'] ?? false,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'tabs': [for (final tab in tabs) tab.toJson()],
    'activeIndex': _activeIndex,
    'isPinned': isPinned,
    'type': 'PaneGroupTab',
  };
}
