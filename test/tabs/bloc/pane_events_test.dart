import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

import '../../helpers/memory_settings_cache.dart';

/// מכסה את אירועי החלוניות: הפלת טאב, סגירת חלונית, שינוי יחס והחלפת צדדים
/// — כולם מבוססי נתיב, וכולם חייבים לשמר את זהות החלוניות.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  PdfBookTab leaf(String title) => PdfBookTab(
    book: PdfBook(title: title, path: '/tmp/$title.pdf'),
    pageNumber: 1,
  );

  Future<TabsBloc> blocWith(List<OpenedTab> tabs, {int current = 0}) async {
    final bloc = TabsBloc(repository: _FakeTabsRepository());
    bloc.add(ReplaceAllTabs(tabs, current));
    await bloc.stream.firstWhere((s) => s.tabs.length == tabs.length);
    return bloc;
  }

  List<String> titles(OpenedTab tab) =>
      leafPanes(tab).map((p) => p.title).toList();

  group('DropTabOnPane — הפלה משורת הכרטיסיות', () {
    test('פיצול על קצה מוציא את הטאב מהרשימה ומכניסו לעץ', () async {
      final target = leaf('יעד');
      final dragged = leaf('נגרר');
      final bloc = await blocWith([target, dragged]);

      bloc.add(
        DropTabOnPane(
          tab: dragged,
          targetPath: const [],
          position: PaneDropPosition.end,
        ),
      );
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final root = bloc.state.currentTab!;
      expect(root, isA<CombinedTab>());
      expect(titles(root), ['יעד', 'נגרר']);
      // אותו אובייקט עבר לעץ — לא שוכפל.
      expect(leafPanes(root)[1], same(dragged));

      await bloc.close();
    });

    test('הפלה במרכז מחזירה את החלונית שנדחקה לשורת הכרטיסיות', () async {
      final target = leaf('יעד');
      final dragged = leaf('נגרר');
      final bloc = await blocWith([target, dragged]);

      bloc.add(
        DropTabOnPane(
          tab: dragged,
          targetPath: const [],
          position: PaneDropPosition.center,
        ),
      );
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      // הנגרר תפס את מקום היעד, והיעד חזר לרשימה במקום להישרף.
      expect(bloc.state.tabs[0], same(dragged));
      expect(bloc.state.tabs[1], same(target));

      await bloc.close();
    });

    test('הפלת הטאב הנוכחי על עצמו אינה משנה דבר', () async {
      final only = leaf('יחיד');
      final bloc = await blocWith([only]);

      bloc.add(
        DropTabOnPane(
          tab: only,
          targetPath: const [],
          position: PaneDropPosition.end,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.tabs, [same(only)]);

      await bloc.close();
    });

    test('נתיב יעד לא תקין אינו משנה את המצב', () async {
      final target = leaf('יעד');
      final dragged = leaf('נגרר');
      final bloc = await blocWith([target, dragged]);

      bloc.add(
        DropTabOnPane(
          tab: dragged,
          targetPath: const [kFirstPane],
          position: PaneDropPosition.end,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.tabs, hasLength(2));

      await bloc.close();
    });
  });

  group('DropTabOnPane — הזזה בתוך הטאב', () {
    test('הזזה לקצה שומרת על מספר החלוניות ועל זהותן', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final c = leaf('ג');
      final root = CombinedTab(
        rightTab: a,
        leftTab: CombinedTab(rightTab: b, leftTab: c, axis: SplitAxis.vertical),
      );
      final bloc = await blocWith([root]);

      bloc.add(
        DropTabOnPane(
          tab: b,
          targetPath: const [kFirstPane],
          position: PaneDropPosition.end,
          sourcePath: const [kSecondPane, kFirstPane],
        ),
      );
      await bloc.stream.firstWhere((s) => s.currentTab != root);

      final updated = bloc.state.currentTab!;
      expect(paneCount(updated), 3);
      expect(leafPanes(updated).toSet(), {same(a), same(b), same(c)});
      // הצומת האנכי התרוקן והתמוטט — ג' עלתה למקומו.
      expect(paneAt(updated, const [kSecondPane]), same(c));

      await bloc.close();
    });

    test('הפלה פנימית במרכז מחליפה בין שתי החלוניות', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final root = CombinedTab(rightTab: a, leftTab: b);
      final bloc = await blocWith([root]);

      bloc.add(
        DropTabOnPane(
          tab: a,
          targetPath: const [kSecondPane],
          position: PaneDropPosition.center,
          sourcePath: const [kFirstPane],
        ),
      );
      await bloc.stream.firstWhere((s) => s.currentTab != root);

      final updated = bloc.state.currentTab!;
      expect(bloc.state.tabs, hasLength(1));
      expect(paneAt(updated, const [kFirstPane]), same(b));
      expect(paneAt(updated, const [kSecondPane]), same(a));

      await bloc.close();
    });
  });

  group('ClosePane', () {
    test('סגירת חלונית מותירה את אחותה בטאב', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final bloc = await blocWith([CombinedTab(rightTab: a, leftTab: b)]);

      bloc.add(const ClosePane([kFirstPane]));
      await bloc.stream.firstWhere((s) => s.currentTab is! CombinedTab);

      expect(bloc.state.tabs, [same(b)]);

      await bloc.close();
    });

    test('סגירת חלונית מקוננת מקריסה את הצומת שהתרוקן', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final c = leaf('ג');
      final root = CombinedTab(
        rightTab: a,
        leftTab: CombinedTab(rightTab: b, leftTab: c, axis: SplitAxis.vertical),
      );
      final bloc = await blocWith([root]);

      bloc.add(const ClosePane([kSecondPane, kFirstPane]));
      await bloc.stream.firstWhere((s) => paneCount(s.currentTab!) == 2);

      final updated = bloc.state.currentTab!;
      expect(paneAt(updated, const [kFirstPane]), same(a));
      expect(paneAt(updated, const [kSecondPane]), same(c));

      await bloc.close();
    });

    test('סגירת החלונית האחרונה סוגרת את הטאב כולו', () async {
      final only = leaf('יחיד');
      final other = leaf('אחר');
      final bloc = await blocWith([only, other]);

      bloc.add(const ClosePane([]));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      expect(bloc.state.tabs, [same(other)]);

      await bloc.close();
    });

    test('נתיב לא תקין אינו משנה את המצב', () async {
      final a = leaf('א');
      final b = leaf('ב');
      final bloc = await blocWith([CombinedTab(rightTab: a, leftTab: b)]);

      bloc.add(const ClosePane([kFirstPane, kFirstPane]));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(paneCount(bloc.state.currentTab!), 2);

      await bloc.close();
    });
  });

  group('UpdateSplitRatio ו-SwapSideBySideTabs לפי נתיב', () {
    test('שינוי יחס פוגע בצומת שבנתיב ולא בשורש', () async {
      final inner = CombinedTab(
        rightTab: leaf('ב'),
        leftTab: leaf('ג'),
        axis: SplitAxis.vertical,
      );
      final root = CombinedTab(rightTab: leaf('א'), leftTab: inner);
      final bloc = await blocWith([root]);

      bloc.add(const UpdateSplitRatio(0.75, path: [kSecondPane]));
      await bloc.stream.first;

      expect(inner.splitRatio, 0.75);
      expect(root.splitRatio, 0.5);

      await bloc.close();
    });

    test('החלפת צדדים פועלת על הצומת שבנתיב ומשמרת זהות', () async {
      final b = leaf('ב');
      final c = leaf('ג');
      final a = leaf('א');
      final root = CombinedTab(
        rightTab: a,
        leftTab: CombinedTab(rightTab: b, leftTab: c, axis: SplitAxis.vertical),
      );
      final bloc = await blocWith([root]);

      bloc.add(const SwapSideBySideTabs(path: [kSecondPane]));
      await bloc.stream.firstWhere((s) => s.currentTab != root);

      final updated = bloc.state.currentTab!;
      expect(paneAt(updated, const [kFirstPane]), same(a));
      expect(paneAt(updated, const [kSecondPane, kFirstPane]), same(c));
      expect(paneAt(updated, const [kSecondPane, kSecondPane]), same(b));

      await bloc.close();
    });
  });
}

class _FakeTabsRepository extends TabsRepository {
  @override
  List<OpenedTab> loadTabs() => const [];

  @override
  int loadCurrentTabIndex() => 0;

  @override
  SideBySideMode? loadSideBySideMode() => null;

  @override
  Future<void> saveTabs(
    List<OpenedTab> tabs,
    int currentTabIndex, [
    SideBySideMode? sideBySideMode,
  ]) async {}

  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {}
}
