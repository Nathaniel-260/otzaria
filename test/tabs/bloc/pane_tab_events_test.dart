import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pane_group_tab.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

import '../../helpers/memory_settings_cache.dart';

/// אירועי הכרטיסיות שבתוך חלונית: בחירה, סגירה, סידור והוצאה חזרה לשורה.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  PdfBookTab leaf(String title) => PdfBookTab(
    book: PdfBook(title: title, path: '/tmp/$title.pdf'),
    pageNumber: 1,
  );

  Future<TabsBloc> blocWith(List<OpenedTab> tabs) async {
    final bloc = TabsBloc(repository: _FakeTabsRepository());
    bloc.add(ReplaceAllTabs(tabs, 0));
    await bloc.stream.firstWhere((s) => s.tabs.length == tabs.length);
    return bloc;
  }

  /// טאב מפוצל: חלונית ימנית עם שתי כרטיסיות, שמאלית עם אחת.
  ({CombinedTab root, PaneGroupTab right, PaneGroupTab left}) split() {
    final right = PaneGroupTab(tabs: [leaf('א'), leaf('ב')]);
    final left = PaneGroupTab(tabs: [leaf('ג')]);
    return (
      root: CombinedTab(rightTab: right, leftTab: left),
      right: right,
      left: left,
    );
  }

  group('ShowPaneTab', () {
    test('מציג את הכרטיסייה ומסמן את חלוניתה כפעילה', () async {
      final t = split();
      final bloc = await blocWith([t.root]);
      addTearDown(bloc.close);

      bloc.add(ShowPaneTab(t.right.tabs[1]));
      await bloc.stream.first;

      expect(t.right.activeTab, same(t.right.tabs[1]));
      expect(bloc.state.activePane, same(t.right.tabs[1]));
    });

    test('כרטיסייה שאינה בטאב הנוכחי אינה משנה דבר', () async {
      final t = split();
      final other = leaf('אחר');
      final bloc = await blocWith([t.root, other]);
      addTearDown(bloc.close);

      bloc.add(ShowPaneTab(other));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(t.right.activeIndex, 0);
      expect(bloc.state.currentTabIndex, 0);
    });

    test('כרטיסייה מוסתרת אינה נבחרת כחלונית פעילה מאליה', () async {
      final t = split();
      final bloc = await blocWith([t.root]);
      addTearDown(bloc.close);

      bloc.add(SetActivePane(t.right.tabs[1]));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // 'ב' בעץ אך אינה מוצגת; פוקוס אליה היה הולך למסך שאינו נראה.
      expect(bloc.state.activePane, same(t.right.tabs[0]));
    });
  });

  group('ClosePaneTab', () {
    test('סגירת כרטיסייה מותירה את החלונית ומציגה את השכנה', () async {
      final t = split();
      final closed = t.right.tabs[0];
      final bloc = await blocWith([t.root]);
      addTearDown(bloc.close);

      bloc.add(ClosePaneTab(closed));
      await bloc.stream.first;

      expect(t.right.tabs.map((tab) => tab.title), ['ב']);
      expect(paneCount(bloc.state.currentTab!), 2);
      expect(bloc.state.activePane, same(t.right.tabs[0]));
    });

    test(
      'סגירת הכרטיסייה האחרונה סוגרת את החלונית ומקריסה את הפיצול',
      () async {
        final t = split();
        final bloc = await blocWith([t.root]);
        addTearDown(bloc.close);

        bloc.add(ClosePaneTab(t.left.tabs.single));
        await bloc.stream.firstWhere((s) => s.currentTab is! CombinedTab);

        // לחלונית ששרדה כבר אין רצועה משלה, ולכן כרטיסיותיה חוזרות לשורה
        // במקום להיעלם מאחורי המוצגת.
        expect(bloc.state.tabs.map((tab) => tab.title), ['א', 'ב']);
      },
    );

    test('סגירת הכרטיסייה האחרונה בטאב סוגרת את הטאב', () async {
      final only = PaneGroupTab(tabs: [leaf('יחיד')]);
      final bloc = await blocWith([only]);
      addTearDown(bloc.close);

      bloc.add(ClosePaneTab(only.tabs.single));
      await bloc.stream.firstWhere((s) => s.tabs.isEmpty);

      expect(bloc.state.tabs, isEmpty);
    });
  });

  group('ReorderPaneTab', () {
    test('סידור מחדש בתוך החלונית שומר על המוצגת', () async {
      final t = split();
      final bloc = await blocWith([t.root]);
      addTearDown(bloc.close);
      final shown = t.right.activeTab;

      bloc.add(ReorderPaneTab(t.right.tabs[0], 1));
      await bloc.stream.first;

      expect(t.right.tabs.map((tab) => tab.title), ['ב', 'א']);
      expect(t.right.activeTab, same(shown));
    });
  });

  group('ExtractPaneTab', () {
    test('הוצאת כרטיסייה מחלונית מרובה מחזירה אותה לשורה', () async {
      final t = split();
      final extracted = t.right.tabs[1];
      final bloc = await blocWith([t.root]);
      addTearDown(bloc.close);

      bloc.add(ExtractPaneTab(extracted));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.tabs[1], same(extracted));
      expect(t.right.tabs.map((tab) => tab.title), ['א']);
      expect(paneCount(bloc.state.tabs[0]), 2, reason: 'הפיצול נשמר');
    });

    test('הוצאת הכרטיסייה היחידה סוגרת את החלונית ומקריסה את הפיצול', () async {
      final t = split();
      final extracted = t.left.tabs.single;
      final bloc = await blocWith([t.root]);
      addTearDown(bloc.close);

      bloc.add(ExtractPaneTab(extracted));
      await bloc.stream.firstWhere((s) => s.tabs.length == 3);

      expect(bloc.state.tabs[0], isNot(isA<CombinedTab>()));
      // החלונית ששרדה אינה בפיצול, ולכן כרטיסיותיה חוזרות לשורה — והמוצאת
      // נכנסת אחריהן ולא ביניהן.
      expect(bloc.state.tabs.map((tab) => tab.title), ['א', 'ב', 'ג']);
      expect(bloc.state.tabs.last, same(extracted));
    });

    test('מיקום ההכנסה נשמר', () async {
      final t = split();
      final extracted = t.right.tabs[1];
      final tail = leaf('אחרון');
      final bloc = await blocWith([t.root, tail]);
      addTearDown(bloc.close);

      bloc.add(ExtractPaneTab(extracted, insertIndex: 0));
      await bloc.stream.firstWhere((s) => s.tabs.length == 3);

      expect(bloc.state.tabs.first, same(extracted));
      expect(bloc.state.currentTabIndex, 0);
    });
  });
}
