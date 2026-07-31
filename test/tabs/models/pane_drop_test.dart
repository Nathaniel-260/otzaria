import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pane_group_tab.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/tab.dart';

class _LeafTab extends OpenedTab {
  _LeafTab(super.title);

  @override
  Map<String, dynamic> toJson() => {'type': '_LeafTab', 'title': title};
}

/// חלונית עם כרטיסייה אחת — כך נראה כל עלה בעץ אחרי פיצול.
PaneGroupTab _pane(OpenedTab tab) => PaneGroupTab(tabs: [tab]);

/// `א | (ב מעל ג)`, כשכל עלה הוא חלונית עם כרטיסייה אחת.
({CombinedTab root, _LeafTab a, _LeafTab b, _LeafTab c}) _tree() {
  final a = _LeafTab('א');
  final b = _LeafTab('ב');
  final c = _LeafTab('ג');
  return (
    root: CombinedTab(
      rightTab: _pane(a),
      leftTab: CombinedTab(
        rightTab: _pane(b),
        leftTab: _pane(c),
        axis: SplitAxis.vertical,
      ),
    ),
    a: a,
    b: b,
    c: c,
  );
}

List<String> _titles(OpenedTab root) =>
    leafPanes(root).map((p) => p.title).toList();

void main() {
  group('הפלה חיצונית', () {
    test('פיצול על קצה מוסיף חלונית ושומר את הקיימות', () {
      final t = _tree();
      final incoming = _LeafTab('חדש');

      final root = applyPaneDrop(
        root: t.root,
        incoming: incoming,
        targetPath: const [kFirstPane],
        position: PaneDropPosition.bottom,
      )!;

      expect(paneCount(root), 4);
      expect(_titles(root), ['א', 'חדש', 'ב', 'ג']);
      expect(
        paneAt(root, const [kSecondPane, kFirstPane]),
        isA<PaneGroupTab>(),
      );
      expect(leafPanes(paneAt(root, const [kSecondPane, kFirstPane])!), [
        same(t.b),
      ]);
    });

    test('הפלה במרכז מוסיפה כרטיסייה לחלונית ואינה דוחקת דבר', () {
      final t = _tree();
      final incoming = _LeafTab('חדש');

      final root = applyPaneDrop(
        root: t.root,
        incoming: incoming,
        targetPath: const [kSecondPane, kFirstPane],
        position: PaneDropPosition.center,
      )!;

      // מספר החלוניות לא השתנה — רק מספר הכרטיסיות שבאחת מהן.
      expect(paneCount(root), 3);
      expect(_titles(root), ['א', 'ב', 'חדש', 'ג']);
      final pane =
          paneAt(root, const [kSecondPane, kFirstPane]) as PaneGroupTab;
      expect(pane.tabs, [same(t.b), same(incoming)]);
      expect(pane.activeTab, same(incoming), reason: 'הנכנסת היא המוצגת');
    });

    test('הפלה על חלונית יחידה מפצלת אותה ועוטפת את שני הצדדים', () {
      final leaf = _LeafTab('יחיד');
      final root =
          applyPaneDrop(
                root: leaf,
                incoming: _LeafTab('חדש'),
                targetPath: const [],
                position: PaneDropPosition.start,
              )!
              as CombinedTab;

      expect(paneCount(root), 2);
      expect(root.first, isA<PaneGroupTab>());
      expect(root.first.title, 'חדש');
      expect((root.second as PaneGroupTab).tabs, [same(leaf)]);
    });

    test('הפלה במרכז של טאב שאינו מפוצל אינה עושה דבר', () {
      final leaf = _LeafTab('יחיד');

      // בשורש אין רצועת כרטיסיות משלו — שורת הכרטיסיות של החלון היא הרצועה,
      // והכרטיסייה כבר שם.
      final root = applyPaneDrop(
        root: leaf,
        incoming: _LeafTab('חדש'),
        targetPath: const [],
        position: PaneDropPosition.center,
      );

      expect(root, isNull);
    });
  });

  group('הזזה פנימית', () {
    test('גרירת כרטיסייה למרכז חלונית אחרת מעבירה אותה אליה', () {
      final t = _tree();

      final root = applyPaneDrop(
        root: t.root,
        incoming: t.a,
        targetPath: const [kSecondPane, kSecondPane],
        sourcePath: const [kFirstPane],
        position: PaneDropPosition.center,
      )!;

      // חלונית א' התרוקנה ונסגרה, והצומת שמעליה קרס.
      expect(paneCount(root), 2);
      expect(_titles(root), ['ב', 'ג', 'א']);
      final target = paneAt(root, const [kSecondPane]) as PaneGroupTab;
      expect(target.tabs, [same(t.c), same(t.a)]);
    });

    test('הזזה לקצה מקריסה את הצומת שהתרוקן ושומרת על מספר החלוניות', () {
      final t = _tree();

      // ב' עוברת מהצומת האנכי אל צדה של א'.
      final root = applyPaneDrop(
        root: t.root,
        incoming: t.b,
        targetPath: const [kFirstPane],
        sourcePath: const [kSecondPane, kFirstPane],
        position: PaneDropPosition.end,
      )!;

      expect(paneCount(root), 3);
      expect(_titles(root), ['א', 'ב', 'ג']);
      // הצומת האנכי התמוטט — ג' עלתה למקומו.
      expect(leafPanes(paneAt(root, const [kSecondPane])!), [same(t.c)]);
      // א' ו-ב' יושבות יחד בצומת החדש.
      final inner = paneAt(root, const [kFirstPane]) as CombinedTab;
      expect(leafPanes(inner.first), [same(t.a)]);
      expect(leafPanes(inner.second), [same(t.b)]);
    });

    test('כל כרטיסיות העץ שומרות על זהותן בהזזה', () {
      final t = _tree();
      final root = applyPaneDrop(
        root: t.root,
        incoming: t.c,
        targetPath: const [kFirstPane],
        sourcePath: const [kSecondPane, kSecondPane],
        position: PaneDropPosition.top,
      )!;

      final leaves = leafPanes(root);
      expect(leaves, containsAll([same(t.a), same(t.b), same(t.c)]));
      expect(leaves.length, 3);
    });

    test('הזזה בין שתי חלוניות בלבד משנה ציר בלי לאבד חלונית', () {
      final a = _LeafTab('א');
      final b = _LeafTab('ב');
      final root = CombinedTab(rightTab: _pane(a), leftTab: _pane(b));

      final result =
          applyPaneDrop(
                root: root,
                incoming: a,
                targetPath: const [kSecondPane],
                sourcePath: const [kFirstPane],
                position: PaneDropPosition.bottom,
              )!
              as CombinedTab;

      expect(paneCount(result), 2);
      expect(result.axis, SplitAxis.vertical);
      expect(leafPanes(result.first), [same(b)]);
      expect(leafPanes(result.second), [same(a)]);
    });

    test('גרירת כרטיסייה אל קצה חלוניתה שלה מפצלת אותה', () {
      final a = _LeafTab('א');
      final b = _LeafTab('ב');
      final shared = PaneGroupTab(tabs: [a, b]);
      final other = _LeafTab('ג');
      final root = CombinedTab(rightTab: shared, leftTab: _pane(other));

      final result = applyPaneDrop(
        root: root,
        incoming: b,
        targetPath: const [kFirstPane],
        sourcePath: const [kFirstPane],
        position: PaneDropPosition.bottom,
      )!;

      expect(paneCount(result), 3);
      expect(shared.tabs, [same(a)], reason: 'ב\' יצאה מהחלונית המשותפת');
      expect(_titles(result), ['א', 'ב', 'ג']);
    });
  });

  group('קלט חריג', () {
    test('נתיב יעד לא תקין זורק', () {
      final t = _tree();
      expect(
        () => applyPaneDrop(
          root: t.root,
          incoming: _LeafTab('חדש'),
          targetPath: const [kFirstPane, kFirstPane],
          position: PaneDropPosition.center,
        ),
        throwsArgumentError,
      );
    });

    test('נתיב מקור לא תקין זורק', () {
      final t = _tree();
      expect(
        () => applyPaneDrop(
          root: t.root,
          incoming: t.a,
          targetPath: const [kFirstPane],
          sourcePath: const [kFirstPane, kSecondPane],
          position: PaneDropPosition.end,
        ),
        throwsArgumentError,
      );
    });

    test('גרירת הכרטיסייה היחידה אל חלוניתה שלה אינה משנה דבר', () {
      final t = _tree();

      for (final position in [
        PaneDropPosition.end,
        PaneDropPosition.center,
        PaneDropPosition.top,
      ]) {
        final result = applyPaneDrop(
          root: t.root,
          incoming: t.a,
          targetPath: const [kFirstPane],
          sourcePath: const [kFirstPane],
          position: position,
        );
        expect(result, isNull, reason: 'מיקום $position');
      }
      expect(paneCount(t.root), 3);
    });
  });
}
