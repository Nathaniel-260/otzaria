import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pane_group_tab.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/pane_drop_target.dart';

class _LeafTab extends OpenedTab {
  _LeafTab(super.title);

  @override
  Map<String, dynamic> toJson() => {'type': '_LeafTab', 'title': title};
}

/// תופס את הקריאות ל-onDrop של המטרה הנבדקת.
class _DropLog {
  PaneDragData? data;
  PanePath? path;
  PaneDropPosition? position;
  int count = 0;

  void record(PaneDragData d, PanePath p, PaneDropPosition pos) {
    data = d;
    path = p;
    position = pos;
    count++;
  }
}

void main() {
  const paneKey = Key('pane');
  const handleKey = Key('handle');

  Widget host({
    required _DropLog log,
    required PaneDragData dragData,
    PanePath targetPath = const [],
    OpenedTab? pane,
  }) {
    // ברירת המחדל היא חלונית עם רצועת כרטיסיות — כך נראית כל חלונית בטאב
    // מפוצל, ורק לה יש אזור מרכז.
    final targetPane = pane ?? PaneGroupTab(tabs: [_LeafTab('יעד')]);
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Column(
            children: [
              Draggable<PaneDragData>(
                data: dragData,
                feedback: const SizedBox(
                  width: 40,
                  height: 20,
                  child: ColoredBox(color: Color(0xFF000000)),
                ),
                child: const SizedBox(
                  key: handleKey,
                  width: 40,
                  height: 20,
                  child: ColoredBox(color: Color(0xFF888888)),
                ),
              ),
              Expanded(
                child: PaneDropTarget(
                  key: paneKey,
                  path: targetPath,
                  pane: targetPane,
                  onDrop: log.record,
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

  /// גוררת מהידית אל [target] ומשחררת שם.
  Future<void> dragTo(WidgetTester tester, Offset target) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(handleKey)),
    );
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('מיפוי הפלה למיקום', () {
    testWidgets('שחרור במרכז מדווח על הוספת כרטיסייה', (tester) async {
      final log = _DropLog();
      await tester.pumpWidget(
        host(
          log: log,
          dragData: PaneDragData(tab: _LeafTab('נגרר')),
        ),
      );

      await dragTo(tester, tester.getCenter(find.byKey(paneKey)));

      expect(log.count, 1);
      expect(log.position, PaneDropPosition.center);
      expect(log.data!.tab.title, 'נגרר');
    });

    testWidgets('שחרור בקצה הימני מדווח על פיצול start ב-RTL', (tester) async {
      final log = _DropLog();
      await tester.pumpWidget(
        host(
          log: log,
          dragData: PaneDragData(tab: _LeafTab('נגרר')),
        ),
      );

      final rect = tester.getRect(find.byKey(paneKey));
      await dragTo(tester, Offset(rect.right - 8, rect.center.dy));

      expect(log.position, PaneDropPosition.start);
    });

    testWidgets('שחרור בתחתית מדווח על פיצול תחתון', (tester) async {
      final log = _DropLog();
      await tester.pumpWidget(
        host(
          log: log,
          dragData: PaneDragData(tab: _LeafTab('נגרר')),
        ),
      );

      final rect = tester.getRect(find.byKey(paneKey));
      await dragTo(tester, Offset(rect.center.dx, rect.bottom - 8));

      expect(log.position, PaneDropPosition.bottom);
    });

    testWidgets('הנתיב המדווח הוא נתיב חלונית היעד', (tester) async {
      final log = _DropLog();
      await tester.pumpWidget(
        host(
          log: log,
          dragData: PaneDragData(tab: _LeafTab('נגרר')),
          targetPath: const [kSecondPane, kFirstPane],
        ),
      );

      await dragTo(tester, tester.getCenter(find.byKey(paneKey)));

      expect(log.path, [kSecondPane, kFirstPane]);
    });
  });

  group('חיווי ויזואלי', () {
    testWidgets('החיווי מופיע בזמן ריחוף ונעלם בשחרור', (tester) async {
      final log = _DropLog();
      await tester.pumpWidget(
        host(
          log: log,
          dragData: PaneDragData(tab: _LeafTab('נגרר')),
        ),
      );

      Finder preview() => find.descendant(
        of: find.byKey(paneKey),
        matching: find.byType(AnimatedPositioned),
      );
      expect(preview(), findsNothing);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(handleKey)),
      );
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byKey(paneKey)));
      await tester.pump();

      expect(preview(), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(preview(), findsNothing);
    });

    testWidgets('יציאה מהחלונית מסירה את החיווי', (tester) async {
      final log = _DropLog();
      await tester.pumpWidget(
        host(
          log: log,
          dragData: PaneDragData(tab: _LeafTab('נגרר')),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(handleKey)),
      );
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byKey(paneKey)));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byKey(handleKey)));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(paneKey),
          matching: find.byType(AnimatedPositioned),
        ),
        findsNothing,
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(log.count, 0);
    });
  });

  group('גרירה עצמית', () {
    testWidgets('חלונית אינה מקבלת גרירה של עצמה', (tester) async {
      final log = _DropLog();
      final tab = _LeafTab('אני');
      await tester.pumpWidget(
        host(
          log: log,
          dragData: PaneDragData(tab: tab, sourcePath: const [kFirstPane]),
          targetPath: const [kFirstPane],
        ),
      );

      await dragTo(tester, tester.getCenter(find.byKey(paneKey)));

      expect(log.count, 0);
      expect(
        find.descendant(
          of: find.byKey(paneKey),
          matching: find.byType(AnimatedPositioned),
        ),
        findsNothing,
      );
    });

    testWidgets('חלונית אחות באותו טאב כן מקבלת', (tester) async {
      final log = _DropLog();
      await tester.pumpWidget(
        host(
          log: log,
          dragData: PaneDragData(
            tab: _LeafTab('אחות'),
            sourcePath: const [kFirstPane],
          ),
          targetPath: const [kSecondPane],
        ),
      );

      await dragTo(tester, tester.getCenter(find.byKey(paneKey)));

      expect(log.count, 1);
      expect(log.data!.sourcePath, [kFirstPane]);
    });

    testWidgets('גרירת הכרטיסיה שהחלונית מציגה אינה מתקבלת ואינה מסמנת', (
      tester,
    ) async {
      final log = _DropLog();
      final displayed = _LeafTab('המוצג');
      await tester.pumpWidget(
        host(
          log: log,
          // אותה כרטיסיה שמוצגת כאן, כפי שקורה בגרירת הכרטיסיה הפעילה.
          dragData: PaneDragData(tab: displayed),
          pane: displayed,
        ),
      );

      await dragTo(tester, tester.getCenter(find.byKey(paneKey)));

      expect(log.count, 0, reason: 'ה-bloc היה דוחה הפלה כזו בכל מקרה');
      expect(
        find.descendant(
          of: find.byKey(paneKey),
          matching: find.byType(AnimatedPositioned),
        ),
        findsNothing,
        reason: 'חיווי שמבטיח פיצול שלא יקרה',
      );
    });

    testWidgets('גרירת טאב מפוצל על אחת מחלוניותיו אינה מתקבלת', (
      tester,
    ) async {
      final log = _DropLog();
      final inner = _LeafTab('פנימית');
      final dragged = CombinedTab(rightTab: inner, leftTab: _LeafTab('אחות'));
      await tester.pumpWidget(
        host(
          log: log,
          dragData: PaneDragData(tab: dragged),
          pane: inner,
        ),
      );

      await dragTo(tester, tester.getCenter(find.byKey(paneKey)));

      expect(log.count, 0);
    });

    testWidgets('טאב אחר כן מתקבל על אותה חלונית', (tester) async {
      final log = _DropLog();
      await tester.pumpWidget(
        host(
          log: log,
          dragData: PaneDragData(tab: _LeafTab('אחר')),
          pane: _LeafTab('המוצג'),
        ),
      );

      await dragTo(tester, tester.getCenter(find.byKey(paneKey)));

      expect(log.count, 1);
    });
  });

  group('חלונית קטנה מדי לפיצול', () {
    testWidgets('בחלונית צרה הקצוות האופקיים אינם מפצלים', (tester) async {
      final log = _DropLog();
      tester.view.physicalSize = const Size(240, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          log: log,
          dragData: PaneDragData(tab: _LeafTab('נגרר')),
        ),
      );

      final pane = tester.getRect(find.byKey(paneKey));
      await dragTo(tester, Offset(pane.right - 6, pane.center.dy));

      // רוחב 240 לא מאפשר שתי חלוניות שמישות, ולכן הקצה נופל למרכז.
      expect(log.count, 1);
      expect(log.position, PaneDropPosition.center);
    });
  });

  group('חלונית בלי רצועת כרטיסיות', () {
    testWidgets('בטאב שאינו מפוצל אין אזור מרכז — גם האמצע מפצל', (
      tester,
    ) async {
      final log = _DropLog();
      await tester.pumpWidget(
        host(
          log: log,
          dragData: PaneDragData(tab: _LeafTab('נגרר')),
          // כרטיסייה בודדת בשורש: הרצועה שלה היא שורת הכרטיסיות של החלון,
          // ולכן אין לאן "להוסיף כרטיסייה" והמרכז מפצל לפי הצלע הארוכה.
          pane: _LeafTab('יעד'),
        ),
      );

      await dragTo(tester, tester.getCenter(find.byKey(paneKey)));

      expect(log.count, 1);
      expect(log.position, isNot(PaneDropPosition.center));
    });
  });
}
