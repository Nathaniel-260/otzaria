import 'dart:convert';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/workspaces/workspace.dart';

import '../helpers/memory_settings_cache.dart';

/// שמירת שולחן עבודה שכולל טאב מפוצל: המבנה, הצירים והיחסים חייבים לשרוד
/// את המסלול לדיסק וחזרה בכל עומק קינון, וטאבי מפרשי PDF חייבים להיגזם
/// גם כשהם מקוננים בתוך חלונית.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  PdfBookTab pdf(String title) => PdfBookTab(
    book: PdfBook(title: title, path: '/tmp/$title.pdf'),
    pageNumber: 3,
  );

  PdfCommentatorsTab commentators(String title) =>
      PdfCommentatorsTab(sourceTab: pdf(title));

  Workspace roundTrip(Workspace workspace) => Workspace.fromJson(
    jsonDecode(jsonEncode(workspace.toJson())) as Map<String, dynamic>,
  );

  List<String> titles(OpenedTab tab) =>
      leafPanes(tab).map((pane) => pane.title).toList();

  group('הלוך-ושוב של טאב מפוצל', () {
    test('מבנה, צירים ויחסים נשמרים בעומק שלוש', () {
      final deep = CombinedTab(
        rightTab: pdf('א'),
        leftTab: CombinedTab(
          rightTab: CombinedTab(
            rightTab: pdf('ב'),
            leftTab: pdf('ג'),
            axis: SplitAxis.vertical,
            splitRatio: 0.3,
          ),
          leftTab: pdf('ד'),
          splitRatio: 0.65,
        ),
        splitRatio: 0.4,
      );

      final restored = roundTrip(
        Workspace(name: 'שולחן', tabs: [deep]),
      );

      expect(restored.tabs, hasLength(1));
      final root = restored.tabs.first as CombinedTab;
      expect(titles(root), ['א', 'ב', 'ג', 'ד']);
      expect(root.axis, SplitAxis.horizontal);
      expect(root.splitRatio, 0.4);

      final middle = paneAt(root, const [kSecondPane]) as CombinedTab;
      expect(middle.splitRatio, 0.65);
      final inner =
          paneAt(root, const [kSecondPane, kFirstPane]) as CombinedTab;
      expect(inner.axis, SplitAxis.vertical);
      expect(inner.splitRatio, 0.3);
    });

    test('מספר טאבים מפוצלים ורגילים שומרים על הסדר ועל הטאב הפעיל', () {
      final workspace = Workspace(
        name: 'שולחן',
        tabs: [
          pdf('רגיל'),
          CombinedTab(
            rightTab: pdf('מפוצל א'),
            leftTab: pdf('מפוצל ב'),
            axis: SplitAxis.vertical,
          ),
          pdf('אחרון'),
        ],
        activeTabIndex: 1,
      );

      final restored = roundTrip(workspace);

      expect(restored.tabs.map(titles), [
        ['רגיל'],
        ['מפוצל א', 'מפוצל ב'],
        ['אחרון'],
      ]);
      expect(restored.activeTabIndex, 1);
      expect((restored.tabs[1] as CombinedTab).axis, SplitAxis.vertical);
    });
  });

  group('גיזום מפרשי PDF', () {
    test('חלונית מפרשים מקוננת נגזמת והמבנה שסביבה מתקרס', () {
      final tab = CombinedTab(
        rightTab: pdf('ספר'),
        leftTab: CombinedTab(
          rightTab: commentators('ספר'),
          leftTab: pdf('שני'),
          axis: SplitAxis.vertical,
        ),
      );

      final workspace = Workspace(name: 'שולחן', tabs: [tab]);
      final saved = workspace.toJson();
      expect(jsonEncode(saved).contains('PdfCommentatorsTab'), isFalse);

      final root = roundTrip(workspace).tabs.single as CombinedTab;
      // הצומת הפנימי נשאר עם חלונית אחת בלבד ולכן התקרס אליה.
      expect(titles(root), ['ספר', 'שני']);
      expect(leafPanes(root.leftTab).single, isA<PdfBookTab>());
      expect(paneCount(root), 2);
    });

    test('טאב שכל חלוניותיו מפרשים נושר כליל', () {
      final workspace = Workspace(
        name: 'שולחן',
        tabs: [
          CombinedTab(
            rightTab: commentators('א'),
            leftTab: commentators('ב'),
          ),
          pdf('נשאר'),
        ],
        activeTabIndex: 1,
      );

      final restored = roundTrip(workspace);

      expect(restored.tabs.map((t) => t.title), ['נשאר']);
      // האינדקס הפעיל מותאם לרשימה שנשמרה בפועל.
      expect(restored.activeTabIndex, 0);
    });

    test('נשירת טאב לפני הפעיל מזיזה את האינדקס אחורה', () {
      final workspace = Workspace(
        name: 'שולחן',
        tabs: [
          commentators('נושר'),
          pdf('ראשון'),
          pdf('פעיל'),
        ],
        activeTabIndex: 2,
      );

      final restored = roundTrip(workspace);

      expect(restored.tabs.map((t) => t.title), ['ראשון', 'פעיל']);
      expect(restored.tabs[restored.activeTabIndex].title, 'פעיל');
    });

    test('שולחן עבודה בלי טאבים ששרדו נשמר ריק ולא קורס', () {
      final workspace = Workspace(
        name: 'שולחן',
        tabs: [commentators('א')],
        activeTabIndex: 0,
      );

      final restored = roundTrip(workspace);

      expect(restored.tabs, isEmpty);
      expect(restored.activeTabIndex, 0);
    });

    test('JSON ישן עם טאב מפרשים נושר ואינו נטען כטאב חיפוש רפאים', () {
      // גרסאות קודמות שמרו PdfCommentatorsTab לדיסק, ו-`OpenedTab.fromJson`
      // אינו מכיר את הטיפוס — כל type לא-מוכר נופל ל-SearchingTab.
      final restored = Workspace.fromJson({
        'name': 'שולחן',
        'currentTab': 0,
        'tabs': [
          {
            'type': 'PdfCommentatorsTab',
            'title': 'מפרשים | ספר',
            'isPinned': false,
            'sourceTab': {
              'type': 'PdfBookTab',
              'title': 'ספר',
              'path': '/tmp/ספר.pdf',
              'pageNumber': 1,
            },
            'activeCommentators': <String>[],
          },
          {
            'type': 'PdfBookTab',
            'title': 'נשאר',
            'path': '/tmp/נשאר.pdf',
            'pageNumber': 1,
          },
        ],
      });

      expect(restored.tabs.map((t) => t.title), ['נשאר']);
    });

    test('טאב מפוצל בלי מפרשים אינו משתנה כלל', () {
      final tab = CombinedTab(
        rightTab: pdf('א'),
        leftTab: pdf('ב'),
        splitRatio: 0.35,
      );
      final restored = roundTrip(Workspace(name: 'שולחן', tabs: [tab]));

      final root = restored.tabs.single as CombinedTab;
      expect(titles(root), ['א', 'ב']);
      expect(root.splitRatio, 0.35);
    });
  });
}
