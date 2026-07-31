import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pane_group_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';

class _LeafTab extends OpenedTab {
  _LeafTab(super.title);

  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  @override
  Map<String, dynamic> toJson() => {
    'type': 'ToolTab',
    'toolId': title,
    'title': title,
  };
}

void main() {
  PaneGroupTab makePane(List<String> titles, {int active = 0}) => PaneGroupTab(
    tabs: [for (final title in titles) _LeafTab(title)],
    activeIndex: active,
  );

  group('כרטיסייה מוצגת', () {
    test('הכותרת נגזרת מהכרטיסייה המוצגת ומתעדכנת בהחלפתה', () {
      final pane = makePane(['א', 'ב'], active: 1);
      expect(pane.title, 'ב');

      pane.activeIndex = 0;
      expect(pane.title, 'א');
    });

    test('כתיבה לכותרת נחסמת ואינה נבלעת בשקט', () {
      expect(() => makePane(['א']).title = 'אחר', throwsUnsupportedError);
    });

    test('אינדקס מחוץ לטווח נצמד לגבול ולא קורס', () {
      expect(makePane(['א', 'ב'], active: 9).title, 'ב');
      expect(makePane(['א', 'ב'], active: -3).title, 'א');
    });

    test('showTab מסמן לפי זהות ומחזיר false לכרטיסייה זרה', () {
      final pane = makePane(['א', 'ב']);
      expect(pane.showTab(pane.tabs[1]), isTrue);
      expect(pane.activeTab, same(pane.tabs[1]));
      expect(pane.showTab(_LeafTab('זר')), isFalse);
      expect(pane.activeTab, same(pane.tabs[1]));
    });
  });

  group('הוספה והסרה', () {
    test('הוספה מכניסה במקום המבוקש והופכת למוצגת', () {
      final pane = makePane(['א', 'ג']);
      final added = _LeafTab('ב');

      pane.addTab(added, at: 1);

      expect(pane.tabs.map((t) => t.title), ['א', 'ב', 'ג']);
      expect(pane.activeTab, same(added));
    });

    test('הוספת כרטיסייה שכבר בחלונית רק מציגה אותה', () {
      final pane = makePane(['א', 'ב']);
      pane.addTab(pane.tabs[0]);

      expect(pane.tabs, hasLength(2));
      expect(pane.activeTab.title, 'א');
    });

    test('סגירה עוברת לכרטיסייה שלידה ולא לאחרונה', () {
      final pane = makePane(['א', 'ב', 'ג'], active: 1);
      final closed = pane.tabs[1];

      expect(pane.removeTab(closed), isTrue);
      expect(pane.tabs.map((t) => t.title), ['א', 'ג']);
      expect(pane.activeTab.title, 'ג');
    });

    test('סגירת כרטיסייה שלפני המוצגת אינה מזיזה את התצוגה', () {
      final pane = makePane(['א', 'ב', 'ג'], active: 2);

      pane.removeTab(pane.tabs[0]);

      expect(pane.activeTab.title, 'ג');
    });

    test('הכרטיסייה האחרונה אינה נסגרת — החלונית עצמה היא שנסגרת', () {
      final pane = makePane(['יחיד']);
      expect(pane.removeTab(pane.tabs.first), isFalse);
      expect(pane.tabs, hasLength(1));
    });

    test('סידור מחדש שומר על הכרטיסייה המוצגת', () {
      final pane = makePane(['א', 'ב', 'ג'], active: 2);
      final shown = pane.activeTab;

      pane.moveTab(pane.tabs[0], 2);

      expect(pane.tabs.map((t) => t.title), ['ב', 'ג', 'א']);
      expect(pane.activeTab, same(shown));
    });
  });

  group('עטיפה', () {
    test('כרטיסייה בודדת נעטפת, וחלונית וצומת פיצול חוזרים כמות שהם', () {
      final leaf = _LeafTab('א');
      final wrapped = PaneGroupTab.wrap(leaf);
      expect(wrapped, isA<PaneGroupTab>());
      expect((wrapped as PaneGroupTab).tabs, [same(leaf)]);

      expect(PaneGroupTab.wrap(wrapped), same(wrapped));

      final split = CombinedTab(rightTab: wrapped, leftTab: makePane(['ב']));
      expect(PaneGroupTab.wrap(split), same(split));
    });

    test('העטיפה יורשת הצמדה, כדי ש"סגור הכל" לא ידרוס נעיצה', () {
      final pinned = _LeafTab('נעוץ')..isPinned = true;
      expect(PaneGroupTab.wrap(pinned).isPinned, isTrue);
    });
  });

  test('שחרור החלונית משחרר את כל הכרטיסיות שבה', () {
    final pane = makePane(['א', 'ב']);
    final tabs = pane.tabs.cast<_LeafTab>().toList();

    pane.dispose();

    expect(tabs.every((t) => t.disposed), isTrue);
  });

  group('שמירה לדיסק', () {
    test('הלוך-ושוב משמר את הכרטיסיות ואת המוצגת', () {
      final pane = makePane(['א', 'ב', 'ג'], active: 2);

      final restored = PaneGroupTab.fromJson(pane.toJson());

      expect(restored.tabs.map((t) => t.title), ['א', 'ב', 'ג']);
      expect(restored.activeIndex, 2);
    });

    test('כרטיסייה מטיפוס לא מוכר מדולגת והשאר נטענות', () {
      final json = {
        'type': 'PaneGroupTab',
        'activeIndex': 0,
        'isPinned': false,
        'tabs': [
          {'type': 'ToolTab', 'toolId': 'builtin.calendar', 'title': 'לוח'},
          {'type': 'טיפוס מגרסה עתידית'},
        ],
      };

      final restored = PaneGroupTab.fromJson(json);

      expect(restored.tabs, hasLength(1));
    });

    test('חלונית בלי אף כרטיסייה תקינה נדחית ואינה נטענת ריקה', () {
      final json = {
        'type': 'PaneGroupTab',
        'tabs': [
          {'type': 'טיפוס מגרסה עתידית'},
        ],
      };

      expect(() => PaneGroupTab.fromJson(json), throwsFormatException);
    });

    test('שחזור דרך OpenedTab.fromJson מזהה את הטיפוס', () {
      final restored = OpenedTab.fromJson(makePane(['א', 'ב']).toJson());
      expect(restored, isA<PaneGroupTab>());
      expect((restored as PaneGroupTab).tabs, hasLength(2));
    });
  });
}
