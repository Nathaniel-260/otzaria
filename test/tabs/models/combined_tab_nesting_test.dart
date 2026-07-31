import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pane_group_tab.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';

import '../../helpers/memory_settings_cache.dart';

/// מכסה את מה שקינון [CombinedTab] מוסיף מעבר לפיצול הפשוט: שרשור ציר
/// דרך שכפול ו-persistence, ומלכוד הכפילות שהורג את מפתחות החלוניות.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  PdfBookTab leaf(String title) => PdfBookTab(
    book: PdfBook(title: title, path: '/tmp/$title.pdf'),
    pageNumber: 1,
  );

  /// `(א | ב) מעל (ג | ד)` — עומק 2 בשני צירים, כשכל עלה הוא חלונית.
  CombinedTab quadTree() {
    return CombinedTab(
      rightTab: CombinedTab(
        rightTab: PaneGroupTab(tabs: [leaf('א')]),
        leftTab: PaneGroupTab(tabs: [leaf('ב')]),
        splitRatio: 0.4,
      ),
      leftTab: CombinedTab(
        rightTab: PaneGroupTab(tabs: [leaf('ג')]),
        leftTab: PaneGroupTab(tabs: [leaf('ד')]),
        splitRatio: 0.6,
      ),
      axis: SplitAxis.vertical,
      splitRatio: 0.35,
    );
  }

  group('persistence מקונן', () {
    test('הלוך-ושוב מלא משמר מבנה, צירים ויחסים בכל עומק', () {
      final restored = CombinedTab.fromJson(quadTree().toJson());

      expect(paneCount(restored), 4);
      expect(leafPanes(restored).map((p) => p.title).toList(), [
        'א',
        'ב',
        'ג',
        'ד',
      ]);

      expect(restored.axis, SplitAxis.vertical);
      expect(restored.splitRatio, 0.35);

      final upper = paneAt(restored, const [kFirstPane]) as CombinedTab;
      final lower = paneAt(restored, const [kSecondPane]) as CombinedTab;
      expect(upper.axis, SplitAxis.horizontal);
      expect(upper.splitRatio, 0.4);
      expect(lower.axis, SplitAxis.horizontal);
      expect(lower.splitRatio, 0.6);
    });

    test('עומק שלוש נשמר ונטען במלואו', () {
      final deep = CombinedTab(
        rightTab: leaf('א'),
        leftTab: CombinedTab(
          rightTab: leaf('ב'),
          leftTab: CombinedTab(
            rightTab: leaf('ג'),
            leftTab: leaf('ד'),
            axis: SplitAxis.vertical,
          ),
        ),
      );

      final restored = CombinedTab.fromJson(deep.toJson());
      expect(paneCount(restored), 4);
      expect(
        (paneAt(restored, const [kSecondPane, kSecondPane]) as CombinedTab)
            .axis,
        SplitAxis.vertical,
      );
    });

    test('טאב מפוצל ישן ללא שדה ציר נטען כאופקי', () {
      final legacy = {
        'type': 'CombinedTab',
        'rightTab': leaf('א').toJson(),
        'leftTab': leaf('ב').toJson(),
        'splitRatio': 0.5,
        'isPinned': false,
      };

      final restored = CombinedTab.fromJson(legacy);
      expect(restored.axis, SplitAxis.horizontal);
      expect(paneCount(restored), 2);
    });
  });

  group('שכפול טאב', () {
    test('OpenedTab.from משמר את הציר בכל עומק', () {
      final clone = OpenedTab.from(quadTree()) as CombinedTab;

      // בלי שרשור הציר, כל פיצול אנכי היה הופך לאופקי בשכפול,
      // בביטול סגירה ובהחלפת שולחן עבודה.
      expect(clone.axis, SplitAxis.vertical);
      expect(clone.splitRatio, 0.35);
      expect(paneCount(clone), 4);
      expect(
        (paneAt(clone, const [kFirstPane]) as CombinedTab).splitRatio,
        0.4,
      );
    });

    test('השכפול מייצר חלוניות חדשות ולא משתף אובייקטים', () {
      final original = quadTree();
      final clone = OpenedTab.from(original) as CombinedTab;

      final originalLeaves = leafPanes(original);
      final cloneLeaves = leafPanes(clone);
      for (var i = 0; i < originalLeaves.length; i++) {
        expect(cloneLeaves[i], isNot(same(originalLeaves[i])));
        expect(cloneLeaves[i].title, originalLeaves[i].title);
      }
    });
  });

  group('מלכוד הכפילות', () {
    test('splitPaneAt עם חלונית שכבר בעץ מייצר אותה פעמיים', () {
      final t = quadTree();
      final existing = paneAt(t, const [kFirstPane, kFirstPane])!;

      // תיעוד מלכוד: splitPaneAt מוסיף בלבד. חלונית כפולה בעץ מייצרת
      // GlobalObjectKey כפול ומפילה את הרינדור — להזזה יש להשתמש
      // ב-applyPaneDrop עם sourcePath.
      final broken = splitPaneAt(
        t,
        const [kSecondPane, kFirstPane],
        existing,
        position: PaneDropPosition.end,
      );

      final leaves = leafPanes(broken);
      expect(leaves.length, 5);
      expect(leaves.toSet().length, 4);
    });

    test('applyPaneDrop עם sourcePath אינו מייצר כפילות', () {
      final t = quadTree();
      final moving = paneAt(t, const [kFirstPane, kFirstPane])!;

      final root = applyPaneDrop(
        root: t,
        incoming: leafPanes(moving).single,
        targetPath: const [kSecondPane, kFirstPane],
        sourcePath: const [kFirstPane, kFirstPane],
        position: PaneDropPosition.end,
      )!;

      final leaves = leafPanes(root);
      expect(leaves.length, 4);
      expect(leaves.toSet().length, 4);
      expect(leaves, contains(same(leafPanes(moving).single)));
    });

    test('הזזה פנימית במרכז מאחדת שתי חלוניות לאחת', () {
      final t = quadTree();
      final source = leafPanes(
        paneAt(t, const [kFirstPane, kFirstPane])!,
      ).single;
      final targetPane =
          paneAt(t, const [kSecondPane, kSecondPane])! as PaneGroupTab;

      final root = applyPaneDrop(
        root: t,
        incoming: source,
        targetPath: const [kSecondPane, kSecondPane],
        sourcePath: const [kFirstPane, kFirstPane],
        position: PaneDropPosition.center,
      )!;

      final leaves = leafPanes(root);
      expect(leaves.length, 4, reason: 'אף ספר לא נסגר');
      expect(leaves.toSet().length, 4);
      // החלונית שהתרוקנה נסגרה, והצומת שמעליה קרס.
      expect(paneCount(root), 3);
      expect(targetPane.tabs, hasLength(2));
      expect(targetPane.activeTab, same(source));
    });
  });

  group('יחס פיצול התחלתי', () {
    test('splitPaneAt מכבד את היחס שנמסר', () {
      final result =
          splitPaneAt(
                leaf('א'),
                const [],
                leaf('חדש'),
                position: PaneDropPosition.end,
                ratio: 0.3,
              )
              as CombinedTab;

      expect(result.splitRatio, 0.3);
    });

    test('applyPaneDrop מעביר את היחס הלאה', () {
      final result = applyPaneDrop(
        root: leaf('א'),
        incoming: leaf('חדש'),
        targetPath: const [],
        position: PaneDropPosition.top,
        ratio: 0.25,
      );

      expect((result! as CombinedTab).splitRatio, 0.25);
    });
  });
}
