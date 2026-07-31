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

/// ציר הפיצול והקינון מהתפריט ("הצג לצד" / "הצג מתחת"), ואיתור טאב פתוח
/// שנמצא כחלונית בעומק — שני המסלולים שהתווספו עם החלוניות המקוננות.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  PdfBookTab pdf(String title, {int page = 1}) => PdfBookTab(
    book: PdfBook(title: title, path: '/tmp/$title.pdf'),
    pageNumber: page,
  );

  Future<TabsBloc> blocWith(List<OpenedTab> tabs, {int current = 0}) async {
    final bloc = TabsBloc(repository: _FakeTabsRepository());
    bloc.add(ReplaceAllTabs(tabs, current));
    await bloc.stream.firstWhere((s) => s.tabs.length == tabs.length);
    return bloc;
  }

  List<String> titles(OpenedTab tab) =>
      leafPanes(tab).map((pane) => pane.title).toList();

  group('EnableSideBySideMode עם ציר', () {
    test('"הצג מתחת" מייצר פיצול אנכי', () async {
      final upper = pdf('עליון');
      final lower = pdf('תחתון');
      final bloc = await blocWith([upper, lower]);

      bloc.add(
        EnableSideBySideMode(
          rightTab: upper,
          leftTab: lower,
          axis: SplitAxis.vertical,
        ),
      );
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final root = bloc.state.currentTab! as CombinedTab;
      expect(root.axis, SplitAxis.vertical);
      // כל צד נעטף בחלונית עם רצועת כרטיסיות משלה; הספר עצמו נשאר הוא-הוא.
      expect(leafPanes(root.rightTab), [same(upper)]);
      expect(leafPanes(root.leftTab), [same(lower)]);

      await bloc.close();
    });

    test('ברירת המחדל נשארת פיצול אופקי', () async {
      final a = pdf('א');
      final b = pdf('ב');
      final bloc = await blocWith([a, b]);

      bloc.add(EnableSideBySideMode(rightTab: a, leftTab: b));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      expect(
        (bloc.state.currentTab! as CombinedTab).axis,
        SplitAxis.horizontal,
      );

      await bloc.close();
    });

    test('טאב שכבר מפוצל קולט חלונית נוספת ומקנן', () async {
      final a = pdf('א');
      final b = pdf('ב');
      final existing = CombinedTab(rightTab: a, leftTab: b);
      final incoming = pdf('ג');
      final bloc = await blocWith([existing, incoming]);

      bloc.add(
        EnableSideBySideMode(
          rightTab: existing,
          leftTab: incoming,
          axis: SplitAxis.vertical,
        ),
      );
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final root = bloc.state.currentTab!;
      expect(paneCount(root), 3);
      expect(titles(root), ['א', 'ב', 'ג']);
      // הצומת הקיים נכנס כמות שהוא — החלוניות שבתוכו לא נבנו מחדש.
      expect(paneAt(root, const [kFirstPane]), same(existing));
      expect(paneAt(root, const [kFirstPane, kFirstPane]), same(a));

      await bloc.close();
    });

    test('הצמדה של אחד הצדדים עוברת לטאב המפוצל', () async {
      final a = pdf('א')..isPinned = true;
      final b = pdf('ב');
      final bloc = await blocWith([a, b]);

      bloc.add(EnableSideBySideMode(rightTab: a, leftTab: b));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      expect(bloc.state.currentTab!.isPinned, isTrue);

      await bloc.close();
    });

    test('פירוק עץ מאוזן מחזיר את ארבע החלוניות בסדר התצוגה', () async {
      final leaves = [pdf('א'), pdf('ב'), pdf('ג'), pdf('ד')];
      final nested = CombinedTab(
        rightTab: CombinedTab(
          rightTab: leaves[0],
          leftTab: leaves[1],
          axis: SplitAxis.vertical,
        ),
        leftTab: CombinedTab(rightTab: leaves[2], leftTab: leaves[3]),
      );
      final bloc = await blocWith([nested]);

      bloc.add(const DisableSideBySideMode(0));
      await bloc.stream.firstWhere((s) => s.tabs.length == 4);

      expect(bloc.state.tabs, [
        same(leaves[0]),
        same(leaves[1]),
        same(leaves[2]),
        same(leaves[3]),
      ]);

      await bloc.close();
    });
  });

  group('אירועי חלונית על טאב שאינו הפעיל', () {
    test('החלפת צדדים פועלת על הטאב שנמסר ולא על המוצג', () async {
      final activeSplit = CombinedTab(rightTab: pdf('א'), leftTab: pdf('ב'));
      final otherSplit = CombinedTab(rightTab: pdf('ג'), leftTab: pdf('ד'));
      final bloc = await blocWith([activeSplit, otherSplit], current: 0);

      bloc.add(const SwapSideBySideTabs(tabIndex: 1));
      await bloc.stream.first;

      // לחיצה ימנית אינה מחליפה טאב פעיל, ולכן הפעולה חייבת לכבד את האינדקס.
      expect(titles(bloc.state.tabs[1]), ['ד', 'ג']);
      expect(titles(bloc.state.tabs[0]), ['א', 'ב']);
      expect(bloc.state.currentTabIndex, 0);

      await bloc.close();
    });

    test('סגירת חלונית פועלת על הטאב שנמסר', () async {
      final activeSplit = CombinedTab(rightTab: pdf('א'), leftTab: pdf('ב'));
      final otherSplit = CombinedTab(rightTab: pdf('ג'), leftTab: pdf('ד'));
      final bloc = await blocWith([activeSplit, otherSplit], current: 0);

      bloc.add(const ClosePane([kFirstPane], tabIndex: 1));
      await bloc.stream.first;

      expect(titles(bloc.state.tabs[1]), ['ד']);
      expect(titles(bloc.state.tabs[0]), ['א', 'ב']);

      await bloc.close();
    });

    test('אינדקס טאב מחוץ לטווח אינו משנה דבר', () async {
      final split = CombinedTab(rightTab: pdf('א'), leftTab: pdf('ב'));
      final bloc = await blocWith([split]);

      bloc.add(const ClosePane([kFirstPane], tabIndex: 7));
      bloc.add(const SwapSideBySideTabs(tabIndex: -1));
      await pumpEventQueue();

      expect(titles(bloc.state.currentTab!), ['א', 'ב']);

      await bloc.close();
    });

    test('בלי אינדקס הפעולה חלה על הטאב הפעיל', () async {
      final first = CombinedTab(rightTab: pdf('א'), leftTab: pdf('ב'));
      final second = CombinedTab(rightTab: pdf('ג'), leftTab: pdf('ד'));
      final bloc = await blocWith([first, second], current: 1);

      bloc.add(const SwapSideBySideTabs());
      await bloc.stream.first;

      expect(titles(bloc.state.tabs[1]), ['ד', 'ג']);
      expect(titles(bloc.state.tabs[0]), ['א', 'ב']);

      await bloc.close();
    });
  });

  group('איתור ספר פתוח בעומק', () {
    test('פתיחת ספר שנמצא כחלונית מקוננת ממקדת את הטאב ואינה מוסיפה', () async {
      final nestedLeaf = pdf('ספר פנימי');
      final nested = CombinedTab(
        rightTab: pdf('חיצוני'),
        leftTab: CombinedTab(
          rightTab: nestedLeaf,
          leftTab: pdf('שכן'),
          axis: SplitAxis.vertical,
        ),
      );
      final bloc = await blocWith([pdf('אחר'), nested], current: 0);

      bloc.add(OpenOrFocusTab(pdf('ספר פנימי')));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 1);

      expect(bloc.state.tabs, hasLength(2), reason: 'לא נוסף טאב חדש');
      expect(bloc.state.currentTab, same(nested));

      await bloc.close();
    });

    test('ניווט מסימניה מגיע אל החלונית המקוננת עצמה', () async {
      final nestedLeaf = pdf('ספר פנימי', page: 5);
      final nested = CombinedTab(
        rightTab: pdf('חיצוני'),
        leftTab: CombinedTab(
          rightTab: nestedLeaf,
          leftTab: pdf('שכן'),
          axis: SplitAxis.vertical,
        ),
      );
      final bloc = await blocWith([pdf('אחר'), nested], current: 0);

      // כמו פתיחת סימניה: הספר כבר פתוח, והמיקום המבוקש מועבר אליו.
      bloc.add(
        OpenOrFocusTab(
          pdf('ספר פנימי', page: 42),
          navigateToPositionIfReused: true,
        ),
      );
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 1);
      await pumpEventQueue();

      expect(bloc.state.tabs, hasLength(2), reason: 'לא נוסף טאב חדש');
      expect(nestedLeaf.pageNumber, 42);

      await bloc.close();
    });

    test('ספר שאינו פתוח באף חלונית נפתח כטאב חדש', () async {
      final nested = CombinedTab(
        rightTab: pdf('א'),
        leftTab: CombinedTab(
          rightTab: pdf('ב'),
          leftTab: pdf('ג'),
          axis: SplitAxis.vertical,
        ),
      );
      final bloc = await blocWith([nested]);

      bloc.add(OpenOrFocusTab(pdf('חדש')));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.tabs.last.title, 'חדש');

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
