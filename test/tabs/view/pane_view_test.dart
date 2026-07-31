import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pane_group_tab.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/view/pane_tab_strip.dart';
import 'package:otzaria/tabs/view/pane_view.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

import '../../helpers/memory_settings_cache.dart';

class _LeafTab extends OpenedTab {
  _LeafTab(super.title);

  @override
  Map<String, dynamic> toJson() => {'type': '_LeafTab', 'title': title};
}

/// סופר בנייה מחדש של תוכן כרטיסייה — הכלי למדידת שימור מיקום הקריאה.
class _CountingContent extends StatefulWidget {
  final String label;
  static final Map<String, int> initCount = {};

  const _CountingContent(this.label);

  @override
  State<_CountingContent> createState() => _CountingContentState();
}

class _CountingContentState extends State<_CountingContent> {
  @override
  void initState() {
    super.initState();
    _CountingContent.initCount.update(
      widget.label,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        const AppTopBar(center: Text('כותרת הספר')),
        Expanded(child: Center(child: Text('תוכן ${widget.label}'))),
      ],
    ),
  );
}

class _FakeSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _FakeSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _StubTabsBloc(super.initial) {
    on<TabsEvent>((event, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    _CountingContent.initCount.clear();
  });

  Future<void> pumpPane(WidgetTester tester, OpenedTab pane) async {
    final root = CombinedTab(
      rightTab: pane,
      leftTab: PaneGroupTab(tabs: [_LeafTab('שכן')]),
    );
    final bloc = _StubTabsBloc(TabsState(tabs: [root], currentTabIndex: 0));
    addTearDown(bloc.close);
    final settings = _FakeSettingsBloc();
    addTearDown(settings.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<TabsBloc>.value(value: bloc),
              BlocProvider<SettingsBloc>.value(value: settings),
            ],
            child: PaneView(
              pane: pane,
              path: const [kFirstPane],
              contentBuilder: (tab) => _CountingContent(tab.title),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('רצועה בתוך הסרגל העליון', () {
    testWidgets('הרצועה תופסת את מקום הכותרת ואינה מוסיפה שורה', (
      tester,
    ) async {
      await pumpPane(
        tester,
        PaneGroupTab(tabs: [_LeafTab('בראשית'), _LeafTab('שמות')]),
      );

      // הרצועה בתוך הסרגל — ולכן הכותרת שלו אינה מוצגת יותר.
      expect(
        find.descendant(
          of: find.byType(AppTopBar),
          matching: find.byType(PaneTabStrip),
        ),
        findsOneWidget,
      );
      expect(find.text('כותרת הספר'), findsNothing);
      // הכרטיסייה המוסתרת נשארת בעץ אך מחוץ לבמה, ולכן נספרת רק עם
      // skipOffstage: false.
      expect(find.byType(AppTopBar), findsOneWidget);
      expect(find.byType(AppTopBar, skipOffstage: false), findsNWidgets(2));
    });

    testWidgets('חלונית בלי רצועה מציגה את הכותרת הרגילה', (tester) async {
      await pumpPane(tester, _LeafTab('בודד'));

      expect(find.byType(PaneTabStrip), findsNothing);
      expect(find.text('כותרת הספר'), findsOneWidget);
    });

    testWidgets('טאב כלי מקבל שורת רצועה נפרדת, כי אין לו סרגל משלו', (
      tester,
    ) async {
      expect(paneHostsTabStrip(_LeafTab('ספר')), isTrue);
      expect(
        paneHostsTabStrip(ToolTab(toolId: 'builtin.calendar', title: 'לוח')),
        isFalse,
      );
    });
  });

  group('כרטיסיות מוסתרות', () {
    testWidgets('כל הכרטיסיות נשארות בעץ — מעבר ביניהן אינו טוען מחדש', (
      tester,
    ) async {
      final pane = PaneGroupTab(tabs: [_LeafTab('א'), _LeafTab('ב')]);
      await pumpPane(tester, pane);

      expect(_CountingContent.initCount['א'], 1);
      expect(_CountingContent.initCount['ב'], 1, reason: 'גם המוסתרת נבנית');

      pane.activeIndex = 1;
      await pumpPane(tester, pane);

      expect(_CountingContent.initCount['א'], 1);
      expect(_CountingContent.initCount['ב'], 1);
    });

    testWidgets('רק המוצגת מקבלת את הרצועה', (tester) async {
      await pumpPane(
        tester,
        PaneGroupTab(tabs: [_LeafTab('א'), _LeafTab('ב')]),
      );

      // שתי הכרטיסיות בעץ, אבל רצועה אחת בלבד נבנית.
      expect(find.byType(PaneTabStrip), findsOneWidget);
    });

    testWidgets('החלפת כרטיסייה מעבירה אליה את פוקוס המקלדת', (tester) async {
      final pane = PaneGroupTab(tabs: [_LeafTab('א'), _LeafTab('ב')]);
      final focused = <String>[];
      for (final tab in pane.tabs) {
        FocusRepository().registerTabContentFocusRequester(
          tab,
          () => focused.add(tab.title),
        );
        addTearDown(
          () => FocusRepository().unregisterTabContentFocusRequester(tab),
        );
      }

      await pumpPane(tester, pane);
      await tester.pump();
      expect(focused, isEmpty, reason: 'בעלייה אין חטיפת פוקוס');

      pane.activeIndex = 1;
      await pumpPane(tester, pane);
      await tester.pump();

      // בלי זה גלילה בחיצים הייתה ממשיכה בספר שכבר אינו על המסך.
      expect(focused, ['ב']);
    });

    testWidgets('אנימציות הכרטיסיות המוסתרות כבויות', (tester) async {
      await pumpPane(
        tester,
        PaneGroupTab(tabs: [_LeafTab('א'), _LeafTab('ב')]),
      );

      final tickerModes = tester
          .widgetList<TickerMode>(find.byType(TickerMode, skipOffstage: false))
          .toList();
      expect(tickerModes.where((m) => m.enabled), isNotEmpty);
      expect(tickerModes.where((m) => !m.enabled), isNotEmpty);
    });
  });
}
