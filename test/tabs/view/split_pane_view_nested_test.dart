import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/split_pane_view.dart';

class _LeafTab extends OpenedTab {
  _LeafTab(super.title);

  @override
  Map<String, dynamic> toJson() => {'type': '_LeafTab', 'title': title};
}

/// המפרידים מזוהים לפי תווית הנגישות שלהם: בעץ מקונן יש יותר ממפריד אחד,
/// והבחנה לפי מקום בעץ הייתה נשברת בכל שינוי מבנה.
Finder _dividerWithLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

final Finder _verticalDivider = _dividerWithLabel(
  'מפריד בין חלוניות — גרירה למעלה ולמטה',
);
final Finder _horizontalDivider = _dividerWithLabel(
  'מפריד בין חלוניות — גרירה לצדדים',
);

Widget _host(
  OpenedTab root, {
  void Function(PanePath, double)? onRatioChanged,
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SplitPaneView(
          root: root,
          // בלי מרכוז: כך ה-Text מקבל את אילוצי החלונית ומדידת גודלו היא
          // מדידת החלונית עצמה.
          paneBuilder: (pane, path) => Text(pane.title),
          onRatioChanged: onRatioChanged ?? (_, _) {},
        ),
      ),
    ),
  );
}

/// עץ `א | (ב מעל ג)`: מפריד חיצוני אופקי ומפריד פנימי אנכי — כל אחד
/// מזוהה בנפרד.
({CombinedTab root, CombinedTab inner}) _nested() {
  final inner = CombinedTab(
    rightTab: _LeafTab('ב'),
    leftTab: _LeafTab('ג'),
    axis: SplitAxis.vertical,
  );
  return (
    root: CombinedTab(rightTab: _LeafTab('א'), leftTab: inner),
    inner: inner,
  );
}

void main() {
  group('מפריד בעץ מקונן', () {
    testWidgets('גרירת המפריד הפנימי מדווחת על נתיב הצומת הפנימי', (
      tester,
    ) async {
      final tree = _nested();
      PanePath? reportedPath;
      double? reportedRatio;

      await tester.pumpWidget(
        _host(
          tree.root,
          onRatioChanged: (path, ratio) {
            reportedPath = path;
            reportedRatio = ratio;
          },
        ),
      );

      await tester.drag(
        _verticalDivider,
        const Offset(0, 80),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(reportedPath, [kSecondPane]);
      expect(reportedRatio, greaterThan(0.5));
      expect(tree.inner.splitRatio, reportedRatio);
      // הצומת החיצוני לא נגע: אירוע שהיה מדווח נתיב ריק היה משנה אותו.
      expect(tree.root.splitRatio, 0.5);
    });

    testWidgets('גרירת המפריד החיצוני מדווחת על נתיב ריק', (tester) async {
      final tree = _nested();
      PanePath? reportedPath;

      await tester.pumpWidget(
        _host(tree.root, onRatioChanged: (path, _) => reportedPath = path),
      );

      await tester.drag(
        _horizontalDivider,
        const Offset(-80, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(reportedPath, isEmpty);
      expect(tree.root.splitRatio, greaterThan(0.5));
      expect(tree.inner.splitRatio, 0.5);
    });

    testWidgets('גרירה אופקית אינה מזיזה מפריד אנכי', (tester) async {
      final tree = _nested();
      final reported = <double>[];

      await tester.pumpWidget(
        _host(tree.root, onRatioChanged: (_, ratio) => reported.add(ratio)),
      );

      await tester.drag(
        _verticalDivider,
        const Offset(120, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // המפריד קורא רק את התזוזה בציר שלו, ולכן היחס אינו זז.
      expect(tree.inner.splitRatio, 0.5);
      expect(reported, everyElement(0.5));
      expect(tree.root.splitRatio, 0.5);
    });

    testWidgets('לחיצה כפולה על המפריד הפנימי מאפסת רק אותו', (tester) async {
      final inner = CombinedTab(
        rightTab: _LeafTab('ב'),
        leftTab: _LeafTab('ג'),
        axis: SplitAxis.vertical,
        splitRatio: 0.85,
      );
      final root = CombinedTab(
        rightTab: _LeafTab('א'),
        leftTab: inner,
        splitRatio: 0.7,
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

      await tester.tap(_verticalDivider, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(_verticalDivider, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(reportedPath, [kSecondPane]);
      expect(reportedRatio, 0.5);
      expect(root.splitRatio, 0.7, reason: 'הצומת החיצוני נשאר כשהיה');
    });
  });

  group('יחסי קצה', () {
    testWidgets('יחס קרוב ל-1 עדיין מציג את שתי החלוניות', (tester) async {
      final root = CombinedTab(
        rightTab: _LeafTab('גדולה'),
        leftTab: _LeafTab('זעירה'),
        splitRatio: 0.999,
      );
      await tester.pumpWidget(_host(root));

      // חסימת ה-flex ל-1..999 מבטיחה שאף חלונית לא נעלמת לחלוטין.
      expect(find.text('גדולה'), findsOneWidget);
      expect(find.text('זעירה'), findsOneWidget);
      expect(tester.getSize(find.text('זעירה')).width, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('יחס קרוב ל-0 אינו מפיל את הרינדור', (tester) async {
      final root = CombinedTab(
        rightTab: _LeafTab('זעירה'),
        leftTab: _LeafTab('גדולה'),
        axis: SplitAxis.vertical,
        splitRatio: 0.001,
      );
      await tester.pumpWidget(_host(root));

      expect(find.text('זעירה'), findsOneWidget);
      expect(find.text('גדולה'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('יחס שהשתנה מבחוץ מסתנכרן בבנייה מחדש', (tester) async {
      final root = CombinedTab(
        rightTab: _LeafTab('ימין'),
        leftTab: _LeafTab('שמאל'),
      );
      await tester.pumpWidget(_host(root));
      final widthBefore = tester.getSize(find.text('ימין')).width;

      // כמו טעינת יחס מדיסק או איפוס מהתפריט: אותו אובייקט צומת, ערך חדש.
      root.splitRatio = 0.8;
      await tester.pumpWidget(_host(root));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.text('ימין')).width, greaterThan(widthBefore));
    });
  });

  group('עצים גדולים', () {
    testWidgets('שמונה חלוניות נבנות וכולן מוצגות', (tester) async {
      var root = _LeafTab('ח0') as OpenedTab;
      var counter = 1;
      for (var round = 0; round < 3; round++) {
        for (final path in leafPanePaths(root)) {
          root = splitPaneAt(
            root,
            path,
            _LeafTab('ח${counter++}'),
            position: round.isEven
                ? PaneDropPosition.end
                : PaneDropPosition.bottom,
          );
        }
      }

      await tester.pumpWidget(_host(root));

      expect(paneCount(root), 8);
      for (var i = 0; i < 8; i++) {
        expect(find.text('ח$i'), findsOneWidget, reason: 'חלונית ח$i מוצגת');
      }
      expect(tester.takeException(), isNull);
      // ארבעה מפרידים אופקיים ושלושה אנכיים — אחד לכל צומת פיצול.
      expect(
        _horizontalDivider.evaluate().length +
            _verticalDivider.evaluate().length,
        7,
      );
    });

    testWidgets('חלונית צרה מאוד אינה קורסת בגרירת מפריד', (tester) async {
      // ארבע חלוניות באותו ציר: המקום לכל אחת קטן, וההגבלה בפיקסלים היא מה
      // שמונע כיווץ לרוחב בלתי שמיש.
      var root = _LeafTab('ח0') as OpenedTab;
      for (var i = 1; i < 4; i++) {
        root = splitPaneAt(
          root,
          leafPanePaths(root).last,
          _LeafTab('ח$i'),
          position: PaneDropPosition.end,
        );
      }
      final ratios = <double>[];

      await tester.pumpWidget(
        _host(root, onRatioChanged: (_, ratio) => ratios.add(ratio)),
      );

      await tester.drag(
        _horizontalDivider.last,
        const Offset(-5000, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(ratios, isNotEmpty);
      expect(ratios.last, greaterThan(0.0));
      expect(ratios.last, lessThan(1.0));
      for (var i = 0; i < 4; i++) {
        expect(tester.getSize(find.text('ח$i')).width, greaterThan(0));
      }
    });
  });
}
