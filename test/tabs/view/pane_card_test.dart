import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/split_pane_view.dart';
import 'package:otzaria/theme/theme_exports.dart';

class _LeafTab extends OpenedTab {
  _LeafTab(super.title);

  @override
  Map<String, dynamic> toJson() => {'type': '_LeafTab', 'title': title};
}

/// המסגור של החלוניות: כרטיסים מרחפים עם רווח, בלי קווים מפרידים.
void main() {
  Future<ColorScheme> pumpCard(
    WidgetTester tester, {
    required bool isActive,
  }) async {
    late ColorScheme scheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Builder(
          builder: (context) {
            scheme = Theme.of(context).colorScheme;
            return Scaffold(
              body: PaneCard(
                isActive: isActive,
                child: const Text('תוכן'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return scheme;
  }

  BoxDecoration decorationOf(WidgetTester tester) {
    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(PaneCard),
        matching: find.byType(AnimatedContainer),
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('החלונית הפעילה מסומנת בקו בצבע הראשי', (tester) async {
    final scheme = await pumpCard(tester, isActive: true);

    final border = decorationOf(tester).border! as Border;
    expect(
      border.top.color,
      AppSurfaces.paneCardBorder(scheme, isActive: true),
    );
  });

  testWidgets('חלונית שאינה פעילה מקבלת מסגרת עמומה', (tester) async {
    final scheme = await pumpCard(tester, isActive: false);

    final border = decorationOf(tester).border! as Border;
    expect(
      border.top.color,
      AppSurfaces.paneCardBorder(scheme, isActive: false),
    );
    expect(
      AppSurfaces.paneCardBorder(scheme, isActive: false),
      isNot(AppSurfaces.paneCardBorder(scheme, isActive: true)),
      reason: 'בלי הבדל אין חיווי לחלונית הפעילה',
    );
  });

  testWidgets('הפינות מעוגלות והתוכן נחתך אליהן', (tester) async {
    await pumpCard(tester, isActive: false);

    expect(
      decorationOf(tester).borderRadius,
      BorderRadius.circular(kPaneCardRadius),
    );
    expect(
      find.descendant(
        of: find.byType(PaneCard),
        matching: find.byType(ClipRRect),
      ),
      findsOneWidget,
    );
  });

  group('רקע הרווח שבין החלוניות', () {
    Future<void> pumpTree(WidgetTester tester, OpenedTab root) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SplitPaneView(
                root: root,
                paneBuilder: (pane, path) => Text(pane.title),
                onRatioChanged: (_, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('טאב מפוצל מקבל רקע רווח שממנו הכרטיסים בולטים', (
      tester,
    ) async {
      await pumpTree(
        tester,
        CombinedTab(rightTab: _LeafTab('א'), leftTab: _LeafTab('ב')),
      );

      expect(
        find.descendant(
          of: find.byType(SplitPaneView),
          matching: find.byType(ColoredBox),
        ),
        findsOneWidget,
      );
    });

    testWidgets('טאב שאינו מפוצל ממלא את המסך בלי מסגור', (tester) async {
      await pumpTree(tester, _LeafTab('יחיד'));

      expect(
        find.descendant(
          of: find.byType(SplitPaneView),
          matching: find.byType(ColoredBox),
        ),
        findsNothing,
      );
    });
  });

  group('המפריד', () {
    testWidgets('במנוחה הידית שקופה — הרווח הוא ההפרדה', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SplitPaneView(
                root: CombinedTab(
                  rightTab: _LeafTab('א'),
                  leftTab: _LeafTab('ב'),
                ),
                paneBuilder: (pane, path) => Text(pane.title),
                onRatioChanged: (_, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 0);
    });
  });
}
