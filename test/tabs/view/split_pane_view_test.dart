import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/split_pane_view.dart';
import 'package:otzaria/widgets/layout/split_pane_content_inset.dart';

class _LeafTab extends OpenedTab {
  _LeafTab(super.title);

  @override
  Map<String, dynamic> toJson() => {'type': '_LeafTab', 'title': title};
}

/// סופר כמה פעמים אותחל מחדש תוכן חלונית — הכלי שבו נמדד שימור ה-State.
class _CountingPane extends StatefulWidget {
  final String label;
  static final Map<String, int> initCount = {};

  const _CountingPane(this.label, {super.key});

  static void reset() => initCount.clear();

  @override
  State<_CountingPane> createState() => _CountingPaneState();
}

class _CountingPaneState extends State<_CountingPane> {
  /// ערך שנצבר בזמן ריצה — מדמה מיקום גלילה או controller של PDF.
  int scrollPosition = 0;

  @override
  void initState() {
    super.initState();
    _CountingPane.initCount.update(
      widget.label,
      (v) => v + 1,
      ifAbsent: () => 1,
    );
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

Widget _host(
  OpenedTab root, {
  void Function(PanePath, double)? onRatioChanged,
  Widget Function(OpenedTab, PanePath)? paneBuilder,
}) {
  return MaterialApp(
    // עובי המפריד תלוי בפלטפורמה (רחב יותר במגע); כאן נבדקת התנהגות העכבר.
    theme: ThemeData(platform: TargetPlatform.windows),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SplitPaneView(
          root: root,
          paneBuilder:
              paneBuilder ??
              (pane, path) => _CountingPane(pane.title, key: ValueKey(pane)),
          onRatioChanged: onRatioChanged ?? (_, _) {},
        ),
      ),
    ),
  );
}

void main() {
  setUp(_CountingPane.reset);

  group('פריסה', () {
    testWidgets('חלונית בודדת מוצגת ללא מפריד', (tester) async {
      await tester.pumpWidget(_host(_LeafTab('א')));

      expect(find.text('א'), findsOneWidget);
      expect(find.byType(Row), findsNothing);
    });

    testWidgets('פיצול אופקי מציג את שתי החלוניות זו לצד זו', (tester) async {
      final root = CombinedTab(
        rightTab: _LeafTab('ימין'),
        leftTab: _LeafTab('שמאל'),
      );
      await tester.pumpWidget(_host(root));

      expect(find.text('ימין'), findsOneWidget);
      expect(find.text('שמאל'), findsOneWidget);

      // ב-RTL החלונית הראשונה יושבת בימין.
      final right = tester.getCenter(find.text('ימין'));
      final left = tester.getCenter(find.text('שמאל'));
      expect(right.dx, greaterThan(left.dx));
      expect(right.dy, closeTo(left.dy, 0.5));
    });

    testWidgets('פיצול אנכי מציג את החלונית הראשונה למעלה', (tester) async {
      final root = CombinedTab(
        rightTab: _LeafTab('עליון'),
        leftTab: _LeafTab('תחתון'),
        axis: SplitAxis.vertical,
      );
      await tester.pumpWidget(_host(root));

      final top = tester.getCenter(find.text('עליון'));
      final bottom = tester.getCenter(find.text('תחתון'));
      expect(top.dy, lessThan(bottom.dy));
      expect(top.dx, closeTo(bottom.dx, 0.5));
    });

    testWidgets('קינון מייצר ארבע חלוניות בפריסת רבעים', (tester) async {
      final root = CombinedTab(
        rightTab: CombinedTab(
          rightTab: _LeafTab('ימין-עליון'),
          leftTab: _LeafTab('ימין-תחתון'),
          axis: SplitAxis.vertical,
        ),
        leftTab: CombinedTab(
          rightTab: _LeafTab('שמאל-עליון'),
          leftTab: _LeafTab('שמאל-תחתון'),
          axis: SplitAxis.vertical,
        ),
      );
      await tester.pumpWidget(_host(root));

      final ru = tester.getCenter(find.text('ימין-עליון'));
      final rd = tester.getCenter(find.text('ימין-תחתון'));
      final lu = tester.getCenter(find.text('שמאל-עליון'));
      final ld = tester.getCenter(find.text('שמאל-תחתון'));

      expect(ru.dx, greaterThan(lu.dx));
      expect(ru.dy, lessThan(rd.dy));
      expect(ld.dx, closeTo(lu.dx, 0.5));
      expect(ld.dy, closeTo(rd.dy, 0.5));
    });
  });

  group('שוליי תוכן', () {
    Future<Map<String, EdgeInsets>> capture(
      WidgetTester tester,
      OpenedTab root,
    ) async {
      final insets = <String, EdgeInsets>{};
      await tester.pumpWidget(
        _host(
          root,
          paneBuilder: (pane, path) => Builder(
            builder: (context) {
              insets[pane.title] = SplitPaneContentInset.of(
                context,
              ).resolve(TextDirection.rtl);
              return Text(pane.title);
            },
          ),
        ),
      );
      return insets;
    }

    testWidgets('חלונית יחידה אינה מקבלת שוליים', (tester) async {
      final insets = await capture(tester, _LeafTab('א'));
      expect(insets['א'], EdgeInsets.zero);
    });

    testWidgets('פיצול אופקי מפצה כל חלונית בצד הנגדי למפריד', (tester) async {
      final insets = await capture(
        tester,
        CombinedTab(rightTab: _LeafTab('ימין'), leftTab: _LeafTab('שמאל')),
      );

      // הימנית גובלת במפריד בשמאלה ולכן מפוצה בימין, ולהפך.
      expect(insets['ימין']!.right, kPaneDividerThickness);
      expect(insets['ימין']!.left, 0);
      expect(insets['שמאל']!.left, kPaneDividerThickness);
      expect(insets['שמאל']!.right, 0);
    });

    testWidgets('חלונית אמצעית הגובלת בשני מפרידים אינה מפוצה', (tester) async {
      final insets = await capture(
        tester,
        CombinedTab(
          rightTab: _LeafTab('ימין'),
          leftTab: CombinedTab(
            rightTab: _LeafTab('אמצע'),
            leftTab: _LeafTab('שמאל'),
          ),
        ),
      );

      expect(insets['אמצע']!.left, 0);
      expect(insets['אמצע']!.right, 0);
      expect(insets['ימין']!.right, kPaneDividerThickness);
      expect(insets['שמאל']!.left, kPaneDividerThickness);
    });

    testWidgets('פיצול אנכי מפצה בציר האנכי', (tester) async {
      final insets = await capture(
        tester,
        CombinedTab(
          rightTab: _LeafTab('עליון'),
          leftTab: _LeafTab('תחתון'),
          axis: SplitAxis.vertical,
        ),
      );

      expect(insets['עליון']!.top, kPaneDividerThickness);
      expect(insets['עליון']!.bottom, 0);
      expect(insets['תחתון']!.bottom, kPaneDividerThickness);
      expect(insets['תחתון']!.top, 0);
    });
  });

  group('גרירת מפריד', () {
    testWidgets('גרירה אופקית ב-RTL מגדילה את החלונית הימנית', (tester) async {
      final root = CombinedTab(
        rightTab: _LeafTab('ימין'),
        leftTab: _LeafTab('שמאל'),
      );
      PanePath? reportedPath;
      double? reportedRatio;

      await tester.pumpWidget(
        _host(
          root,
          onRatioChanged: (path, ratio) {
            reportedPath = path;
            reportedRatio = ratio;
          },
        ),
      );

      final widthBefore = tester.getSize(find.text('ימין')).width;
      await tester.drag(
        find.byType(MouseRegion).last,
        const Offset(-100, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(reportedPath, isEmpty);
      expect(reportedRatio, greaterThan(0.5));
      expect(tester.getSize(find.text('ימין')).width, greaterThan(widthBefore));
      // היחס נשמר על הצומת עצמו, כדי שבנייה מחדש לא תאבד את הגרירה.
      expect(root.splitRatio, reportedRatio);
    });

    testWidgets('גרירה אינה מכווצת חלונית מתחת למינימום', (tester) async {
      final root = CombinedTab(
        rightTab: _LeafTab('ימין'),
        leftTab: _LeafTab('שמאל'),
      );
      double? reportedRatio;

      await tester.pumpWidget(
        _host(root, onRatioChanged: (_, ratio) => reportedRatio = ratio),
      );

      await tester.drag(
        find.byType(MouseRegion).last,
        const Offset(5000, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(reportedRatio, greaterThan(0.0));
      expect(tester.getSize(find.text('ימין')).width, greaterThan(0));
    });

    testWidgets('לחיצה כפולה מאפסת את היחס לחצי', (tester) async {
      final root = CombinedTab(
        rightTab: _LeafTab('ימין'),
        leftTab: _LeafTab('שמאל'),
        splitRatio: 0.8,
      );
      double? reportedRatio;

      await tester.pumpWidget(
        _host(root, onRatioChanged: (_, ratio) => reportedRatio = ratio),
      );

      await tester.tap(find.byType(MouseRegion).last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(MouseRegion).last, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(reportedRatio, 0.5);
    });
  });

  group('שימור State בשינוי מבנה העץ', () {
    testWidgets('פיצול חלונית אינו מאתחל מחדש את החלוניות הקיימות', (
      tester,
    ) async {
      final a = _LeafTab('א');
      final b = _LeafTab('ב');
      var root = CombinedTab(rightTab: a, leftTab: b) as OpenedTab;

      await tester.pumpWidget(_host(root));
      expect(_CountingPane.initCount['א'], 1);
      expect(_CountingPane.initCount['ב'], 1);

      // מדמה מצב ריצה שנצבר בחלונית — מיקום גלילה, controller וכד'.
      tester
              .state<_CountingPaneState>(find.byType(_CountingPane).first)
              .scrollPosition =
          42;

      // פיצול החלונית השנייה בונה עץ חדש לגמרי מעל אותם עלים.
      root = splitPaneAt(
        root,
        const [kSecondPane],
        _LeafTab('ג'),
        position: PaneDropPosition.bottom,
      );
      await tester.pumpWidget(_host(root));

      expect(find.text('ג'), findsOneWidget);
      // זהו החוזה: העלים הקיימים עברו מקום בעץ בלי אתחול מחדש.
      expect(_CountingPane.initCount['א'], 1);
      expect(_CountingPane.initCount['ב'], 1);
      expect(_CountingPane.initCount['ג'], 1);
      expect(
        tester
            .state<_CountingPaneState>(find.byType(_CountingPane).first)
            .scrollPosition,
        42,
      );
    });

    testWidgets('סגירת חלונית אינה מאתחל מחדש את אחותה', (tester) async {
      final t = (a: _LeafTab('א'), b: _LeafTab('ב'), c: _LeafTab('ג'));
      var root =
          CombinedTab(
                rightTab: t.a,
                leftTab: CombinedTab(
                  rightTab: t.b,
                  leftTab: t.c,
                  axis: SplitAxis.vertical,
                ),
              )
              as OpenedTab;

      await tester.pumpWidget(_host(root));
      expect(_CountingPane.initCount['ג'], 1);

      // הסרת ב' מקריסה את הצומת האנכי — ג' עולה במעלה העץ.
      root = removePaneAt(root, const [kSecondPane, kFirstPane])!;
      await tester.pumpWidget(_host(root));

      expect(find.text('ב'), findsNothing);
      expect(_CountingPane.initCount['א'], 1);
      expect(_CountingPane.initCount['ג'], 1);
    });

    testWidgets('החלפת צדדים אינה מאתחל מחדש את החלוניות', (tester) async {
      final a = _LeafTab('א');
      final b = _LeafTab('ב');
      var root = CombinedTab(rightTab: a, leftTab: b) as OpenedTab;

      await tester.pumpWidget(_host(root));
      final xBefore = tester.getCenter(find.text('א')).dx;

      root = swapPanesAt(root, const []);
      await tester.pumpWidget(_host(root));

      expect(tester.getCenter(find.text('א')).dx, lessThan(xBefore));
      expect(_CountingPane.initCount['א'], 1);
      expect(_CountingPane.initCount['ב'], 1);
    });

    testWidgets('שינוי ציר אינו מאתחל מחדש את החלוניות', (tester) async {
      final a = _LeafTab('א');
      final b = _LeafTab('ב');
      var root = CombinedTab(rightTab: a, leftTab: b) as OpenedTab;

      await tester.pumpWidget(_host(root));
      root = (root as CombinedTab).copyWith(axis: SplitAxis.vertical);
      await tester.pumpWidget(_host(root));

      expect(
        tester.getCenter(find.text('א')).dy,
        lessThan(
          tester.getCenter(find.text('ב')).dy,
        ),
      );
      expect(_CountingPane.initCount['א'], 1);
      expect(_CountingPane.initCount['ב'], 1);
    });
  });
}
