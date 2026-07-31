import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// חלונית עלה מינימלית — מבודדת את בדיקות העץ מכל תלות ב-bloc או בספרים.
class _LeafTab extends OpenedTab {
  _LeafTab(super.title);

  @override
  Map<String, dynamic> toJson() => {'type': '_LeafTab', 'title': title};
}

/// אוסף החוקים שחייבים להתקיים בכל עץ חלוניות תקין. הפרה של אחד מהם היא
/// באג רינדור בפועל: זהות כפולה מפילה את המסך במפתח כפול, ונתיב שאינו
/// נפתר חזרה שולח אירועי bloc אל החלונית הלא נכונה.
void _expectTreeInvariants(OpenedTab root, {required String after}) {
  final panes = panesOf(root);
  final paths = leafPanePaths(root);

  expect(paths, hasLength(panes.length), reason: 'נתיב לכל חלונית ($after)');
  expect(paneCount(root), panes.length, reason: 'מנייה עקבית ($after)');

  for (var i = 0; i < panes.length; i++) {
    // הנתיב ה-i מצביע על החלונית ה-i, לפי זהות אובייקט ולא לפי כותרת.
    expect(
      paneAt(root, paths[i]),
      same(panes[i]),
      reason: 'נתיב ↔ חלונית ($after)',
    );
    expect(
      pathOfPane(root, panes[i]),
      paths[i],
      reason: 'pathOfPane הוא ההופכי של paneAt ($after)',
    );
    expect(isValidPanePath(root, paths[i]), isTrue, reason: after);
  }

  // ייחוד לפי זהות: אותו אובייקט פעמיים בעץ = GlobalObjectKey כפול = קריסה.
  final tabs = leafPanes(root);
  expect(
    (Set<OpenedTab>.identity()..addAll(tabs)).length,
    tabs.length,
    reason: 'כרטיסייה מופיעה פעמיים בעץ ($after)',
  );
  // כל כרטיסייה נפתרת לחלונית שלה — אחרת אירועי כרטיסייה מגיעים ליעד שגוי.
  for (final tab in tabs) {
    expect(paneContaining(root, tab), isNotNull, reason: after);
  }
}

/// מתאר את מבנה העץ כטקסט: כותרות עלים, וצירים ויחסים של הצמתים.
String _shape(OpenedTab node) {
  if (node is CombinedTab) {
    final axis = node.axis == SplitAxis.vertical ? 'v' : 'h';
    final ratio = node.splitRatio.toStringAsFixed(3);
    return '($axis:$ratio ${_shape(node.rightTab)} ${_shape(node.leftTab)})';
  }
  return node.title;
}

/// אותו תיאור, אך מתוך ה-JSON — כדי להשוות מבנה לפני ואחרי סריאליזציה
/// בלי להיזקק לעלים שניתן לשחזר.
String _shapeFromJson(Map<String, dynamic> json) {
  if (json['type'] == 'PaneGroupTab') {
    final tabs = (json['tabs'] as List).cast<Map>();
    final active = (json['activeIndex'] as num).toInt();
    return tabs[active]['title'] as String;
  }
  if (json['type'] == 'CombinedTab') {
    final axis = json['axis'] == 'vertical' ? 'v' : 'h';
    final ratio = (json['splitRatio'] as num).toDouble().toStringAsFixed(3);
    final right = _shapeFromJson(
      Map<String, dynamic>.from(json['rightTab'] as Map),
    );
    final left = _shapeFromJson(
      Map<String, dynamic>.from(json['leftTab'] as Map),
    );
    return '($axis:$ratio $right $left)';
  }
  return json['title'] as String;
}

void main() {
  const positions = [
    PaneDropPosition.start,
    PaneDropPosition.end,
    PaneDropPosition.top,
    PaneDropPosition.bottom,
  ];

  group('חוקי העץ תחת סדרת פעולות מקרית', () {
    test('300 פעולות מקריות אינן מפרות אף חוק', () {
      // זרע קבוע: כשל כאן ניתן לשחזור מדויק ולא "פעם בכמה הרצות".
      final random = Random(20260730);
      var root = _LeafTab('בסיס') as OpenedTab;
      var counter = 0;
      var maxPanes = 1;

      for (var step = 0; step < 300; step++) {
        final paths = leafPanePaths(root);
        final leaves = leafPanes(root);
        maxPanes = max(maxPanes, leaves.length);
        // תקרה כדי שהעץ לא יגדל בלי גבול: מעליה נבחרות רק פעולות שאינן
        // מוסיפות חלונית, כך שהסדרה מגלגלת גם הסרות והזזות ולא רק פיצולים.
        final choice = leaves.length >= 10
            ? 5 + random.nextInt(5)
            : random.nextInt(10);

        if (choice < 5 || leaves.length == 1) {
          // פיצול: חלונית חדשה נכנסת ליד חלונית מקרית.
          root = splitPaneAt(
            root,
            paths[random.nextInt(paths.length)],
            _LeafTab('ח${counter++}'),
            position: positions[random.nextInt(positions.length)],
            ratio: 0.2 + random.nextDouble() * 0.6,
          );
          _expectTreeInvariants(root, after: 'פיצול בצעד $step');
        } else if (choice < 7) {
          final removed = removePaneAt(
            root,
            paths[random.nextInt(paths.length)],
          );
          expect(removed, isNotNull, reason: 'נשארה לפחות חלונית אחת');
          root = removed!;
          _expectTreeInvariants(root, after: 'הסרה בצעד $step');
        } else if (choice < 9) {
          // החלפת צדדים של צומת פיצול מקרי.
          final nodePaths = paths
              .where((path) => path.isNotEmpty)
              .map((path) => path.sublist(0, path.length - 1))
              .toList();
          root = swapPanesAt(root, nodePaths[random.nextInt(nodePaths.length)]);
          _expectTreeInvariants(root, after: 'החלפת צדדים בצעד $step');
        } else if (leaves.length >= 3) {
          // הזזה פנימית: חלונית קיימת עוברת ליד חלונית אחרת.
          final sourceIndex = random.nextInt(leaves.length);
          var targetIndex = random.nextInt(leaves.length);
          if (targetIndex == sourceIndex) {
            targetIndex = (targetIndex + 1) % leaves.length;
          }
          final moved = applyPaneDrop(
            root: root,
            incoming: leaves[sourceIndex],
            targetPath: paths[targetIndex],
            position: positions[random.nextInt(positions.length)],
            sourcePath: paths[sourceIndex],
          );
          expect(moved, isNotNull, reason: 'הזזה בין חלוניות שונות מתבצעת');
          root = moved!;
          _expectTreeInvariants(root, after: 'הזזה בצעד $step');
        }
      }

      // הסדרה אכן הגיעה לעצים ממשיים ולא התהפכה בין עלה בודד לשניים.
      expect(maxPanes, 10);
    });

    test('הלוך-ושוב JSON אחרי סדרת פעולות משמר את המבנה במדויק', () {
      final random = Random(7);
      var root = _LeafTab('בסיס') as OpenedTab;
      var counter = 0;

      for (var step = 0; step < 40; step++) {
        root = splitPaneAt(
          root,
          leafPanePaths(root)[random.nextInt(paneCount(root))],
          _LeafTab('ח${counter++}'),
          position: positions[random.nextInt(positions.length)],
          ratio: 0.25 + random.nextDouble() * 0.5,
        );
      }

      final decoded =
          jsonDecode(jsonEncode(root.toJson())) as Map<String, dynamic>;
      expect(_shapeFromJson(decoded), _shape(root));
    });
  });

  group('שינוי מספר החלוניות', () {
    test('פיצול מוסיף חלונית אחת בכל עומק ושומר על הקיימות', () {
      var root = _LeafTab('א') as OpenedTab;
      var expected = ['א'];

      for (var i = 0; i < 6; i++) {
        final before = leafPanes(root);
        final targetPath = leafPanePaths(root).last;
        root = splitPaneAt(
          root,
          targetPath,
          _LeafTab('ח$i'),
          position: PaneDropPosition.bottom,
        );
        expected = [...expected, 'ח$i'];

        expect(paneCount(root), before.length + 1);
        expect(leafPanes(root).map((p) => p.title), expected);
        // כל החלוניות שהיו — אותם אובייקטים, לא העתקים.
        for (final pane in before) {
          expect(pathOfPane(root, pane), isNotNull);
        }
      }

      // פיצול חוזר בקצה מקנן: העומק גדל עם כל צעד.
      expect(leafPanePaths(root).last, hasLength(6));
    });

    test('הסרה מורידה חלונית אחת ומשמרת את יתר הזהויות', () {
      final leaves = [for (var i = 0; i < 5; i++) _LeafTab('ח$i')];
      var root = leaves.first as OpenedTab;
      for (var i = 1; i < leaves.length; i++) {
        root = splitPaneAt(
          root,
          leafPanePaths(root).last,
          leaves[i],
          position: PaneDropPosition.end,
        );
      }

      while (paneCount(root) > 1) {
        final before = leafPanes(root);
        final removedPane = before[before.length ~/ 2];
        final removedPath = pathOfPane(root, removedPane)!;
        root = removePaneAt(root, removedPath)!;

        expect(paneCount(root), before.length - 1);
        expect(pathOfPane(root, removedPane), isNull);
        for (final pane in before.where((p) => p != removedPane)) {
          expect(pathOfPane(root, pane), isNotNull);
        }
        _expectTreeInvariants(root, after: 'הסרה חוזרת');
      }

      expect(root, isNot(isA<CombinedTab>()));
    });
  });

  group('פעולות שאינן משנות את קבוצת החלוניות', () {
    test('החלפת צדדים מחזירה את אותה קבוצה בסדר הפוך', () {
      final a = _LeafTab('א');
      final b = _LeafTab('ב');
      final c = _LeafTab('ג');
      final root = CombinedTab(
        rightTab: a,
        leftTab: CombinedTab(rightTab: b, leftTab: c),
      );

      final swapped = swapPanesAt(root, const []);
      expect(leafPanes(swapped), [same(b), same(c), same(a)]);
      expect(paneCount(swapped), 3);
      _expectTreeInvariants(swapped, after: 'החלפת שורש');

      // החלפה כפולה חוזרת לסדר המקורי.
      final back = swapPanesAt(swapped, const []);
      expect(leafPanes(back).map((p) => p.title), ['א', 'ב', 'ג']);
    });

    test('הזזה פנימית שומרת על מספר החלוניות ועל הקבוצה', () {
      final leaves = [for (var i = 0; i < 4; i++) _LeafTab('ח$i')];
      var root = leaves.first as OpenedTab;
      for (var i = 1; i < leaves.length; i++) {
        root = splitPaneAt(
          root,
          const [],
          leaves[i],
          position: PaneDropPosition.end,
        );
      }
      final before = leafPanes(root).toSet();

      for (final position in positions) {
        final paths = leafPanePaths(root);
        root = applyPaneDrop(
          root: root,
          incoming: leafPanes(root).first,
          targetPath: paths.last,
          position: position,
          sourcePath: paths.first,
        )!;
        expect(paneCount(root), 4);
        expect(leafPanes(root).toSet(), before);
        _expectTreeInvariants(root, after: 'הזזה ל-$position');
      }
    });

    test('גיזום שמקבל את כל החלוניות מחזיר את אותו אובייקט', () {
      final a = _LeafTab('א');
      final root = CombinedTab(
        rightTab: a,
        leftTab: CombinedTab(
          rightTab: _LeafTab('ב'),
          leftTab: _LeafTab('ג'),
          axis: SplitAxis.vertical,
        ),
      );

      expect(prunePanes(root, (_) => true), same(root));

      // גיזום חלקי משמר את זהות מי שנשאר.
      final pruned = prunePanes(root, (pane) => pane.title != 'ב')!;
      expect(leafPanes(pruned).map((p) => p.title), ['א', 'ג']);
      expect(leafPanes(pruned).first, same(a));
      _expectTreeInvariants(pruned, after: 'גיזום');
    });
  });

  group('עצים עמוקים', () {
    test('שמונה חלוניות — כל הנתיבים תקינים והעומק כצפוי', () {
      // בנייה מאוזנת: כל חלונית מפוצלת פעם אחת בכל סבב.
      var root = _LeafTab('ח0') as OpenedTab;
      var counter = 1;
      for (var round = 0; round < 3; round++) {
        for (final path in leafPanePaths(root)) {
          root = splitPaneAt(
            root,
            pathOfPane(root, paneAt(root, path)!)!,
            _LeafTab('ח${counter++}'),
            position: round.isEven
                ? PaneDropPosition.end
                : PaneDropPosition.bottom,
          );
        }
      }

      expect(paneCount(root), 8);
      for (final path in leafPanePaths(root)) {
        expect(path, hasLength(3), reason: 'עץ מאוזן בעומק שלוש');
        expect(paneAt(root, path), isNot(isA<CombinedTab>()));
      }
      _expectTreeInvariants(root, after: 'עץ מאוזן');
    });

    test('נתיב ארוך מדי או צעד לא חוקי אינם קורסים', () {
      final root = CombinedTab(rightTab: _LeafTab('א'), leftTab: _LeafTab('ב'));

      expect(paneAt(root, const [kFirstPane, kFirstPane]), isNull);
      expect(paneAt(root, const [2]), isNull);
      expect(paneAt(root, const [kFirstPane, 7]), isNull);
      expect(isValidPanePath(root, const [kSecondPane, kSecondPane]), isFalse);
      expect(
        () =>
            replacePaneAt(root, const [kFirstPane, kFirstPane], _LeafTab('ג')),
        throwsArgumentError,
      );
    });
  });
}
