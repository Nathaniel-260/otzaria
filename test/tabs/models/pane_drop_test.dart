import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/tab.dart';

class _LeafTab extends OpenedTab {
  _LeafTab(super.title);

  @override
  Map<String, dynamic> toJson() => {'type': '_LeafTab', 'title': title};
}

/// `א | (ב מעל ג)`
({CombinedTab root, _LeafTab a, _LeafTab b, _LeafTab c}) _tree() {
  final a = _LeafTab('א');
  final b = _LeafTab('ב');
  final c = _LeafTab('ג');
  return (
    root: CombinedTab(
      rightTab: a,
      leftTab: CombinedTab(rightTab: b, leftTab: c, axis: SplitAxis.vertical),
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

      final result = applyPaneDrop(
        root: t.root,
        incoming: incoming,
        targetPath: const [kFirstPane],
        position: PaneDropPosition.bottom,
      );

      expect(result.displaced, isNull);
      expect(paneCount(result.root), 4);
      expect(_titles(result.root), ['א', 'חדש', 'ב', 'ג']);
      expect(paneAt(result.root, const [kSecondPane, kFirstPane]), same(t.b));
    });

    test('הפלה במרכז דוחקת את החלונית הקיימת ומחזירה אותה', () {
      final t = _tree();
      final incoming = _LeafTab('חדש');

      final result = applyPaneDrop(
        root: t.root,
        incoming: incoming,
        targetPath: const [kSecondPane, kFirstPane],
        position: PaneDropPosition.center,
      );

      expect(result.displaced, same(t.b));
      expect(paneCount(result.root), 3);
      expect(_titles(result.root), ['א', 'חדש', 'ג']);
    });

    test('הפלה על חלונית יחידה מפצלת אותה', () {
      final leaf = _LeafTab('יחיד');
      final result = applyPaneDrop(
        root: leaf,
        incoming: _LeafTab('חדש'),
        targetPath: const [],
        position: PaneDropPosition.start,
      );

      expect(paneCount(result.root), 2);
      expect((result.root as CombinedTab).first.title, 'חדש');
      expect((result.root as CombinedTab).second, same(leaf));
    });
  });

  group('הזזה פנימית', () {
    test('הפלה במרכז מחליפה בין שתי החלוניות במקומן', () {
      final t = _tree();

      final result = applyPaneDrop(
        root: t.root,
        incoming: t.a,
        targetPath: const [kSecondPane, kSecondPane],
        sourcePath: const [kFirstPane],
        position: PaneDropPosition.center,
      );

      expect(result.displaced, isNull);
      expect(paneCount(result.root), 3);
      expect(paneAt(result.root, const [kFirstPane]), same(t.c));
      expect(paneAt(result.root, const [kSecondPane, kSecondPane]), same(t.a));
      expect(paneAt(result.root, const [kSecondPane, kFirstPane]), same(t.b));
    });

    test('הזזה לקצה מקריסה את הצומת שהתרוקן ושומרת על מספר החלוניות', () {
      final t = _tree();

      // ב' עוברת מהצומת האנכי אל צדה של א'.
      final result = applyPaneDrop(
        root: t.root,
        incoming: t.b,
        targetPath: const [kFirstPane],
        sourcePath: const [kSecondPane, kFirstPane],
        position: PaneDropPosition.end,
      );

      expect(paneCount(result.root), 3);
      expect(_titles(result.root), ['א', 'ב', 'ג']);
      // הצומת האנכי התמוטט — ג' עלתה למקומו.
      expect(paneAt(result.root, const [kSecondPane]), same(t.c));
      // א' ו-ב' יושבות יחד בצומת החדש.
      final inner = paneAt(result.root, const [kFirstPane]) as CombinedTab;
      expect(inner.first, same(t.a));
      expect(inner.second, same(t.b));
    });

    test('כל חלוניות העץ שומרות על זהותן בהזזה', () {
      final t = _tree();
      final result = applyPaneDrop(
        root: t.root,
        incoming: t.c,
        targetPath: const [kFirstPane],
        sourcePath: const [kSecondPane, kSecondPane],
        position: PaneDropPosition.top,
      );

      final leaves = leafPanes(result.root);
      expect(leaves, containsAll([same(t.a), same(t.b), same(t.c)]));
      expect(leaves.length, 3);
    });

    test('הזזה בין שתי חלוניות בלבד משנה ציר בלי לאבד חלונית', () {
      final a = _LeafTab('א');
      final b = _LeafTab('ב');
      final root = CombinedTab(rightTab: a, leftTab: b);

      final result = applyPaneDrop(
        root: root,
        incoming: a,
        targetPath: const [kSecondPane],
        sourcePath: const [kFirstPane],
        position: PaneDropPosition.bottom,
      );

      expect(paneCount(result.root), 2);
      final combined = result.root as CombinedTab;
      expect(combined.axis, SplitAxis.vertical);
      expect(combined.first, same(b));
      expect(combined.second, same(a));
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

    test('הזזת השורש עצמו אינה משנה דבר', () {
      final leaf = _LeafTab('יחיד');
      final result = applyPaneDrop(
        root: leaf,
        incoming: leaf,
        targetPath: const [],
        sourcePath: const [],
        position: PaneDropPosition.end,
      );

      expect(result.root, same(leaf));
      expect(result.displaced, isNull);
    });

    test('הזזת צומת אל חלונית שבתוכו אינה משנה דבר ואינה זורקת', () {
      final t = _tree();

      // היעד נמצא בתוך המקור: הסרת המקור הייתה מוחקת גם את היעד.
      for (final position in [
        PaneDropPosition.end,
        PaneDropPosition.center,
        PaneDropPosition.top,
      ]) {
        final result = applyPaneDrop(
          root: t.root,
          incoming: t.root,
          targetPath: const [kFirstPane],
          sourcePath: const [],
          position: position,
        );
        expect(result.root, same(t.root), reason: 'מיקום $position');
        expect(result.displaced, isNull);
      }
    });
  });
}
