import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import 'package:otzaria/tabs/view/pane_tab_strip.dart';

import '../../helpers/memory_settings_cache.dart';

class _LeafTab extends OpenedTab {
  _LeafTab(super.title);

  @override
  Map<String, dynamic> toJson() => {'type': '_LeafTab', 'title': title};
}

/// bloc שמתעד את האירועים שנשלחו אליו, בלי לעבד אותם.
class _RecordingTabsBloc extends Bloc<TabsEvent, TabsState>
    implements TabsBloc {
  _RecordingTabsBloc(super.initial) {
    on<TabsEvent>((event, _) {});
  }

  final List<TabsEvent> events = [];

  @override
  void add(TabsEvent event) {
    events.add(event);
    super.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  ({
    _RecordingTabsBloc bloc,
    PaneGroupTab pane,
    CombinedTab root,
    OpenedTab other,
  })
  fixture({int tabCount = 2}) {
    final pane = PaneGroupTab(
      tabs: [for (var i = 0; i < tabCount; i++) _LeafTab('ספר $i')],
    );
    final other = _LeafTab('שכן');
    final root = CombinedTab(
      rightTab: pane,
      leftTab: PaneGroupTab(tabs: [other]),
    );
    final extra = _LeafTab('טאב עליון');
    final bloc = _RecordingTabsBloc(
      TabsState(tabs: [root, extra], currentTabIndex: 0),
    );
    return (bloc: bloc, pane: pane, root: root, other: other);
  }

  Future<void> pumpStrip(
    WidgetTester tester,
    _RecordingTabsBloc bloc,
    PaneGroupTab pane, {
    PanePath path = const [kFirstPane],
    double width = 400,
  }) async {
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: BlocProvider<TabsBloc>.value(
            value: bloc,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width,
                  height: 40,
                  child: PaneTabStrip(pane: pane, path: path),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('מציגה כרטיסייה לכל ספר בחלונית', (tester) async {
    final f = fixture(tabCount: 3);
    await pumpStrip(tester, f.bloc, f.pane);

    expect(find.text('ספר 0'), findsOneWidget);
    expect(find.text('ספר 1'), findsOneWidget);
    expect(find.text('ספר 2'), findsOneWidget);
  });

  testWidgets('לחיצה על כרטיסייה מבקשת להציג אותה', (tester) async {
    final f = fixture();
    await pumpStrip(tester, f.bloc, f.pane);

    await tester.tap(find.text('ספר 1'));
    await tester.pump();

    final shown = f.bloc.events.whereType<ShowPaneTab>().toList();
    expect(shown, hasLength(1));
    expect(shown.single.tab, same(f.pane.tabs[1]));
  });

  testWidgets('לחיצה על הכרטיסייה המוצגת אינה שולחת אירוע מיותר', (
    tester,
  ) async {
    final f = fixture();
    await pumpStrip(tester, f.bloc, f.pane);

    await tester.tap(find.text('ספר 0'));
    await tester.pump();

    expect(f.bloc.events.whereType<ShowPaneTab>(), isEmpty);
  });

  testWidgets('כפתור הסגירה סוגר את הכרטיסייה שעליה לחצו', (tester) async {
    final f = fixture();
    await pumpStrip(tester, f.bloc, f.pane);

    // ה-X מוצג על המוצגת; בשאר הוא מופיע רק בהצבעה.
    await tester.tap(find.byTooltip('סגור כרטיסייה'));
    await tester.pump();

    final closed = f.bloc.events.whereType<ClosePaneTab>().toList();
    expect(closed, hasLength(1));
    expect(closed.single.tab, same(f.pane.tabs[0]));
  });

  testWidgets('לחצן אמצעי סוגר כרטיסייה, כמו בדפדפן', (tester) async {
    final f = fixture();
    await pumpStrip(tester, f.bloc, f.pane);

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await gesture.down(tester.getCenter(find.text('ספר 1')));
    await gesture.up();
    await tester.pump();

    final closed = f.bloc.events.whereType<ClosePaneTab>().toList();
    expect(closed, hasLength(1));
    expect(closed.single.tab, same(f.pane.tabs[1]));
    // סגירה בלחצן האמצעי אינה מחליפה קודם את המוצגת.
    expect(f.bloc.events.whereType<ShowPaneTab>(), isEmpty);
  });

  testWidgets('כפתור ההבאה מציע רק טאבים אחרים ומעביר אותם לחלונית', (
    tester,
  ) async {
    final f = fixture();
    await pumpStrip(tester, f.bloc, f.pane);

    await tester.tap(find.byTooltip('הבא כרטיסייה לחלונית זו'));
    await tester.pumpAndSettle();

    // הטאב הנוכחי (המפוצל) אינו יכול להיכנס לתוך עצמו.
    expect(find.text('טאב עליון'), findsOneWidget);
    await tester.tap(find.text('טאב עליון'));
    await tester.pumpAndSettle();

    final drops = f.bloc.events.whereType<DropTabOnPane>().toList();
    expect(drops, hasLength(1));
    expect(drops.single.position, PaneDropPosition.center);
    expect(drops.single.targetPath, [kFirstPane]);
  });

  testWidgets('גרירת כרטיסייה בתוך הרצועה מסדרת מחדש', (tester) async {
    final f = fixture(tabCount: 3);
    await pumpStrip(tester, f.bloc, f.pane);

    final source = tester.getCenter(find.text('ספר 0'));
    final target = tester.getCenter(find.text('ספר 2'));
    final gesture = await tester.startGesture(source);
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final reorders = f.bloc.events.whereType<ReorderPaneTab>().toList();
    expect(reorders, hasLength(1));
    expect(reorders.single.tab, same(f.pane.tabs[0]));
    expect(reorders.single.newIndex, greaterThan(0));
  });

  testWidgets('הכרטיסייה המוצגת מציגה גם את מיקום הקריאה', (tester) async {
    final book = PdfBookTab(
      book: PdfBook(title: 'בראשית', path: '/tmp/b.pdf'),
      pageNumber: 1,
    );
    final hidden = PdfBookTab(
      book: PdfBook(title: 'שמות', path: '/tmp/s.pdf'),
      pageNumber: 1,
    );
    book.currentTitle.value = 'עמוד ז';
    hidden.currentTitle.value = 'עמוד יב';
    final pane = PaneGroupTab(tabs: [book, hidden]);
    final bloc = _RecordingTabsBloc(
      TabsState(tabs: [pane], currentTabIndex: 0),
    );

    await pumpStrip(tester, bloc, pane, path: const []);

    // המיקום היה בכותרת הסרגל שהרצועה תפסה את מקומה; בלעדיו אין חיווי
    // לאיפה בספר אנחנו. בכרטיסייה מוסתרת הוא רק היה מרעיש.
    expect(find.textContaining('עמוד ז'), findsOneWidget);
    expect(find.textContaining('עמוד יב'), findsNothing);

    book.currentTitle.value = 'עמוד ח';
    await tester.pump();
    expect(find.textContaining('עמוד ח'), findsOneWidget);
  });

  testWidgets('בחלונית עם כרטיסייה אחת אין כפילות של אירועי סגירה', (
    tester,
  ) async {
    final f = fixture(tabCount: 1);
    await pumpStrip(tester, f.bloc, f.pane);

    expect(find.text('ספר 0'), findsOneWidget);
    await tester.tap(find.text('ספר 0'));
    await tester.pump();

    expect(f.bloc.events, isEmpty, reason: 'היא כבר המוצגת');
  });
}
