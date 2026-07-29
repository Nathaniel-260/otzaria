import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/reading_tab_strip.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/pane_drop_target.dart';

class _StubTab extends OpenedTab {
  _StubTab(super.title);

  @override
  Map<String, dynamic> toJson() => {'type': '_StubTab', 'title': title};
}

/// תופס את פעולות הרצועה.
class _StripLog {
  OpenedTab? movedTab;
  int? newIndex;
  int moves = 0;
  int dragStarts = 0;

  void reorder(OpenedTab tab, int index) {
    movedTab = tab;
    newIndex = index;
    moves++;
  }
}

void main() {
  const stripKey = Key('strip');
  const paneKey = Key('pane');
  const tabWidth = 100.0;

  /// רצועה עם שלוש כרטיסיות, ולצדה חלונית קריאה שמקבלת גרירות.
  Widget host({
    required _StripLog log,
    required List<OpenedTab> tabs,
    void Function(PaneDragData, PanePath, PaneDropPosition)? onPaneDrop,
    TextDirection textDirection = TextDirection.rtl,
    bool requireLongPress = false,
    // רוחב הרצועה. ברירת המחדל צמודה לכרטיסיות, אך במסך אמיתי היא רחבה
    // מהן — ואז מדידה מול גבולותיה במקום מול השורה מטה את מיקום ההכנסה.
    double? stripWidth,
  }) {
    return MaterialApp(
      home: Directionality(
        textDirection: textDirection,
        child: Scaffold(
          body: Column(
            children: [
              SizedBox(
                key: stripKey,
                height: 40,
                width: stripWidth ?? tabWidth * tabs.length,
                child: ReadingTabStrip(
                  tabs: tabs,
                  widths: [for (final _ in tabs) tabWidth],
                  requireLongPressToDrag: requireLongPress,
                  onReorder: log.reorder,
                  onDragStarted: () => log.dragStarts++,
                  tabBuilder: (tab, index, width) => SizedBox(
                    width: width,
                    child: ColoredBox(
                      color: const Color(0xFFDDDDDD),
                      child: Center(child: Text(tab.title)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PaneDropTarget(
                  key: paneKey,
                  path: const [],
                  pane: _StubTab('מוצג'),
                  onDrop: onPaneDrop ?? (_, _, _) {},
                  child: const ColoredBox(
                    color: Color(0xFFEEEEEE),
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// גוררת מכרטיסיה [from] אל [target] ומשחררת.
  Future<void> dragFrom(
    WidgetTester tester,
    String from,
    Offset target,
  ) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(from)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('סידור מחדש', () {
    testWidgets('גרירה שמאלה ב-RTL מזיזה את הכרטיסיה קדימה ברשימה', (
      tester,
    ) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(host(log: log, tabs: tabs));

      // ב-RTL הכרטיסיה הראשונה בימין; גרירת 'א' שמאלה מעבירה אותה אחרי 'ב'.
      await dragFrom(tester, 'א', tester.getCenter(find.text('ג')));

      expect(log.moves, 1);
      expect(log.movedTab, same(tabs[0]));
      expect(log.newIndex, greaterThan(0));
    });

    testWidgets('גרירה למקום שלא זז אינה שולחת סידור מחדש', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(host(log: log, tabs: tabs));

      await dragFrom(tester, 'ב', tester.getCenter(find.text('ב')));

      expect(log.moves, 0);
    });

    testWidgets('היעד מדווח בקונבנציית הסרה-ואז-הכנסה', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(host(log: log, tabs: tabs));

      // גרירת הכרטיסיה האחרונה אל תחילת הרצועה (הקצה הימני ב-RTL).
      final strip = tester.getRect(find.byKey(stripKey));
      await dragFrom(tester, 'ג', Offset(strip.right - 4, strip.center.dy));

      expect(log.moves, 1);
      expect(log.movedTab, same(tabs[2]));
      expect(log.newIndex, 0, reason: 'הכרטיסיה עוברת לראש הרשימה');
    });

    testWidgets('רצועה רחבה מהכרטיסיות: הגרירה מסדרת לפי מקום המצביע', (
      tester,
    ) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      // המצב הרגיל במסך רחב: 3 כרטיסיות של 100 בתוך רצועה של 700. ב-RTL הן
      // צמודות לימין, וכל השטח הריק שמשמאלן נכנס לחישוב אם מודדים אותו.
      await tester.pumpWidget(host(log: log, tabs: tabs, stripWidth: 700));

      await dragFrom(tester, 'א', tester.getCenter(find.text('ג')));

      expect(log.moves, 1, reason: 'גרירה על כרטיסיה אחרת מסדרת מחדש');
      expect(log.movedTab, same(tabs[0]));
      expect(log.newIndex, 2, reason: "'א' עוברת אל מקומה של 'ג'");
    });

    testWidgets('רצועה רחבה: גרירה על עצמה אינה מזיזה', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(host(log: log, tabs: tabs, stripWidth: 700));

      await dragFrom(tester, 'ב', tester.getCenter(find.text('ב')));

      expect(log.moves, 0);
    });

    testWidgets('רצועה רחבה ב-LTR מסדרת לכיוון הנגדי', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(
        host(
          log: log,
          tabs: tabs,
          stripWidth: 700,
          textDirection: TextDirection.ltr,
        ),
      );

      // תחילת הרשימה ב-LTR היא הקצה השמאלי; מרכז הכרטיסיה הראשונה הוא
      // בדיוק הגבול שבו מיקום ההכנסה מתחלף.
      final strip = tester.getRect(find.byKey(stripKey));
      await dragFrom(tester, 'ג', Offset(strip.left + 4, strip.center.dy));

      expect(log.moves, 1);
      expect(log.newIndex, 0);
    });

    testWidgets('ב-LTR הכיוון מתהפך', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(
        host(log: log, tabs: tabs, textDirection: TextDirection.ltr),
      );

      final strip = tester.getRect(find.byKey(stripKey));
      await dragFrom(tester, 'ג', Offset(strip.left + 4, strip.center.dy));

      expect(log.moves, 1);
      expect(log.newIndex, 0);
    });
  });

  group('חיווי מיקום ההכנסה', () {
    testWidgets('קו החיווי מופיע בגרירה מעל הרצועה ונעלם בשחרור', (
      tester,
    ) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב')];
      await tester.pumpWidget(host(log: log, tabs: tabs));

      Finder line() => find.descendant(
        of: find.byType(ReadingTabStrip),
        matching: find.byType(DecoratedBox),
      );
      final before = line().evaluate().length;

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('א')),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveTo(tester.getCenter(find.text('ב')));
      await tester.pump();

      expect(line().evaluate().length, greaterThan(before));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(line().evaluate().length, before);
    });
  });

  group('גרירה אל חלונית קריאה', () {
    testWidgets('שחרור מעל אזור הקריאה מפצל ואינו מסדר מחדש', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב')];
      PaneDragData? dropped;
      PaneDropPosition? position;

      await tester.pumpWidget(
        host(
          log: log,
          tabs: tabs,
          onPaneDrop: (data, path, pos) {
            dropped = data;
            position = pos;
          },
        ),
      );

      final pane = tester.getRect(find.byKey(paneKey));
      await dragFrom(tester, 'א', Offset(pane.center.dx, pane.bottom - 8));

      expect(dropped, isNotNull, reason: 'ההפלה הגיעה אל חלונית הקריאה');
      expect(dropped!.tab, same(tabs[0]));
      expect(
        dropped!.sourcePath,
        isNull,
        reason: 'כרטיסיה מהרצועה מגיעה בלי נתיב מקור',
      );
      expect(position, PaneDropPosition.bottom);
      expect(log.moves, 0, reason: 'שחרור מחוץ לרצועה אינו מסדר מחדש');
    });

    testWidgets('תחילת גרירה מדווחת פעם אחת', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב')];
      await tester.pumpWidget(host(log: log, tabs: tabs));

      final pane = tester.getRect(find.byKey(paneKey));
      await dragFrom(tester, 'א', pane.center);

      expect(log.dragStarts, 1);
    });
  });

  group('פלטפורמה', () {
    testWidgets('בדסקטופ הגרירה מיידית', (tester) async {
      final log = _StripLog();
      await tester.pumpWidget(
        host(log: log, tabs: [_StubTab('א')]),
      );

      expect(
        find.byWidgetPredicate((w) => w.runtimeType == Draggable<PaneDragData>),
        findsOneWidget,
      );
      expect(find.byType(LongPressDraggable<PaneDragData>), findsNothing);
    });

    testWidgets('במגע נדרשת לחיצה ארוכה', (tester) async {
      final log = _StripLog();
      await tester.pumpWidget(
        host(log: log, tabs: [_StubTab('א')], requireLongPress: true),
      );

      expect(find.byType(LongPressDraggable<PaneDragData>), findsOneWidget);
    });
  });

  group('מקרי קצה', () {
    testWidgets('כרטיסיה יחידה אינה מסדרת מחדש', (tester) async {
      final log = _StripLog();
      await tester.pumpWidget(host(log: log, tabs: [_StubTab('יחיד')]));

      final strip = tester.getRect(find.byKey(stripKey));
      await dragFrom(tester, 'יחיד', Offset(strip.left + 4, strip.center.dy));

      expect(log.moves, 0);
    });

    testWidgets('רצועה ריקה נבנית בלי שגיאה', (tester) async {
      final log = _StripLog();
      await tester.pumpWidget(host(log: log, tabs: const []));

      expect(find.byType(ReadingTabStrip), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
