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

/// בונה עץ: `א | (ב מעל ג)` — פיצול אופקי שהחלונית השנייה שלו מפוצלת אנכית.
({CombinedTab root, _LeafTab a, _LeafTab b, _LeafTab c}) _nestedTree() {
  final a = _LeafTab('א');
  final b = _LeafTab('ב');
  final c = _LeafTab('ג');
  final inner = CombinedTab(
    rightTab: b,
    leftTab: c,
    axis: SplitAxis.vertical,
  );
  final root = CombinedTab(rightTab: a, leftTab: inner);
  return (root: root, a: a, b: b, c: c);
}

void main() {
  group('paneAt', () {
    test('נתיב ריק מחזיר את השורש', () {
      final t = _nestedTree();
      expect(paneAt(t.root, const []), same(t.root));
    });

    test('מאתר חלוניות בכל עומק', () {
      final t = _nestedTree();
      expect(paneAt(t.root, const [kFirstPane]), same(t.a));
      expect(paneAt(t.root, const [kSecondPane, kFirstPane]), same(t.b));
      expect(paneAt(t.root, const [kSecondPane, kSecondPane]), same(t.c));
    });

    test('מחזיר null לנתיב שיורד אל תוך עלה', () {
      final t = _nestedTree();
      expect(paneAt(t.root, const [kFirstPane, kFirstPane]), isNull);
    });

    test('מחזיר null לצעד לא חוקי', () {
      final t = _nestedTree();
      expect(paneAt(t.root, const [7]), isNull);
      expect(isValidPanePath(t.root, const [7]), isFalse);
    });
  });

  group('replacePaneAt', () {
    test('נתיב ריק מחליף את השורש כולו', () {
      final t = _nestedTree();
      final fresh = _LeafTab('חדש');
      expect(replacePaneAt(t.root, const [], fresh), same(fresh));
    });

    test('משמר את זהות האובייקט של חלוניות שלא נגעו בהן', () {
      final t = _nestedTree();
      final fresh = _LeafTab('חדש');
      final updated =
          replacePaneAt(t.root, const [kSecondPane, kFirstPane], fresh)
              as CombinedTab;

      // זהו החוזה שעליו נשען שימור ה-State: כל עלה שלא הוחלף חייב
      // להישאר אותו אובייקט, אחרת GlobalObjectKey שלו ישתנה.
      expect(paneAt(updated, const [kFirstPane]), same(t.a));
      expect(paneAt(updated, const [kSecondPane, kSecondPane]), same(t.c));
      expect(paneAt(updated, const [kSecondPane, kFirstPane]), same(fresh));
    });

    test('משמר ציר ויחס של הצמתים בנתיב', () {
      final t = _nestedTree();
      t.root.splitRatio = 0.3;
      final inner = paneAt(t.root, const [kSecondPane]) as CombinedTab;
      inner.splitRatio = 0.7;

      final updated =
          replacePaneAt(t.root, const [kSecondPane, kFirstPane], _LeafTab('ד'))
              as CombinedTab;

      expect(updated.axis, SplitAxis.horizontal);
      expect(updated.splitRatio, 0.3);
      final updatedInner = paneAt(updated, const [kSecondPane]) as CombinedTab;
      expect(updatedInner.axis, SplitAxis.vertical);
      expect(updatedInner.splitRatio, 0.7);
    });

    test('זורק על נתיב לא תקין', () {
      final t = _nestedTree();
      expect(
        () => replacePaneAt(t.root, const [
          kFirstPane,
          kFirstPane,
        ], _LeafTab('ד')),
        throwsArgumentError,
      );
    });
  });

  group('splitPaneAt', () {
    test('פיצול לימין מכניס את הנגררת ראשונה בציר אופקי', () {
      final leaf = _LeafTab('א');
      final incoming = _LeafTab('חדש');
      final result =
          splitPaneAt(
                leaf,
                const [],
                incoming,
                position: PaneDropPosition.start,
              )
              as CombinedTab;

      expect(result.axis, SplitAxis.horizontal);
      expect(result.first, same(incoming));
      expect(result.second, same(leaf));
    });

    test('פיצול לשמאל מכניס את הנגררת שנייה', () {
      final leaf = _LeafTab('א');
      final incoming = _LeafTab('חדש');
      final result =
          splitPaneAt(leaf, const [], incoming, position: PaneDropPosition.end)
              as CombinedTab;

      expect(result.first, same(leaf));
      expect(result.second, same(incoming));
    });

    test('פיצול למעלה/למטה מייצר ציר אנכי', () {
      final leaf = _LeafTab('א');
      final up =
          splitPaneAt(
                leaf,
                const [],
                _LeafTab('עליון'),
                position: PaneDropPosition.top,
              )
              as CombinedTab;
      final down =
          splitPaneAt(
                leaf,
                const [],
                _LeafTab('תחתון'),
                position: PaneDropPosition.bottom,
              )
              as CombinedTab;

      expect(up.axis, SplitAxis.vertical);
      expect(up.first.title, 'עליון');
      expect(down.axis, SplitAxis.vertical);
      expect(down.second.title, 'תחתון');
    });

    test('הפלה במרכז מחליפה ולא מפצלת', () {
      final t = _nestedTree();
      final incoming = _LeafTab('חדש');
      final result = splitPaneAt(
        t.root,
        const [kFirstPane],
        incoming,
        position: PaneDropPosition.center,
      );

      expect(paneCount(result), 3);
      expect(paneAt(result, const [kFirstPane]), same(incoming));
    });

    test('פיצול חלונית מקוננת מייצר ארבע חלוניות', () {
      final t = _nestedTree();
      final incoming = _LeafTab('ד');
      final result = splitPaneAt(
        t.root,
        const [kSecondPane, kSecondPane],
        incoming,
        position: PaneDropPosition.end,
      );

      expect(paneCount(result), 4);
      expect(
        leafPanes(result).map((p) => p.title).toList(),
        ['א', 'ב', 'ג', 'ד'],
      );
      // שאר החלוניות שמרו על זהותן.
      expect(paneAt(result, const [kFirstPane]), same(t.a));
      expect(paneAt(result, const [kSecondPane, kFirstPane]), same(t.b));
    });
  });

  group('removePaneAt', () {
    test('אחות תופסת את מקום ההורה', () {
      final t = _nestedTree();
      final result = removePaneAt(t.root, const [kSecondPane, kFirstPane]);

      expect(paneCount(result!), 2);
      // הצומת האנכי הפנימי התמוטט — ג' עלה למקומו.
      expect(paneAt(result, const [kSecondPane]), same(t.c));
      expect(paneAt(result, const [kFirstPane]), same(t.a));
    });

    test('הסרת חלונית מפיצול פשוט מותירה עלה בודד', () {
      final a = _LeafTab('א');
      final b = _LeafTab('ב');
      final root = CombinedTab(rightTab: a, leftTab: b);

      expect(removePaneAt(root, const [kFirstPane]), same(b));
      expect(removePaneAt(root, const [kSecondPane]), same(a));
    });

    test('הסרת השורש מחזירה null — הטאב כולו נסגר', () {
      final t = _nestedTree();
      expect(removePaneAt(t.root, const []), isNull);
    });

    test('זורק על נתיב לא תקין', () {
      final t = _nestedTree();
      expect(
        () => removePaneAt(t.root, const [kFirstPane, kFirstPane]),
        throwsArgumentError,
      );
    });
  });

  group('swapPanesAt', () {
    test('מחליף צדדים והופך את היחס', () {
      final t = _nestedTree();
      t.root.splitRatio = 0.3;
      final result = swapPanesAt(t.root, const []) as CombinedTab;

      expect(result.splitRatio, closeTo(0.7, 1e-9));
      expect(result.first, same(paneAt(t.root, const [kSecondPane])));
      expect(result.second, same(t.a));
    });

    test('מחליף צומת מקונן בלי לגעת בשאר העץ', () {
      final t = _nestedTree();
      final result = swapPanesAt(t.root, const [kSecondPane]);

      expect(paneAt(result, const [kFirstPane]), same(t.a));
      expect(paneAt(result, const [kSecondPane, kFirstPane]), same(t.c));
      expect(paneAt(result, const [kSecondPane, kSecondPane]), same(t.b));
    });

    test('זורק כשהנתיב אינו צומת פיצול', () {
      final t = _nestedTree();
      expect(
        () => swapPanesAt(t.root, const [kFirstPane]),
        throwsArgumentError,
      );
    });
  });

  group('סריקת עלים', () {
    test('leafPanePaths מחזיר נתיבים בסדר תצוגה', () {
      final t = _nestedTree();
      expect(leafPanePaths(t.root), [
        [kFirstPane],
        [kSecondPane, kFirstPane],
        [kSecondPane, kSecondPane],
      ]);
    });

    test('עלה בודד הוא חלונית אחת בנתיב ריק', () {
      final leaf = _LeafTab('א');
      expect(paneCount(leaf), 1);
      expect(leafPanePaths(leaf), [<int>[]]);
      expect(leafPanes(leaf), [same(leaf)]);
    });

    test('pathOfPane מאתר לפי זהות אובייקט', () {
      final t = _nestedTree();
      expect(pathOfPane(t.root, t.c), [kSecondPane, kSecondPane]);
      expect(pathOfPane(t.root, t.root), isEmpty);
      expect(pathOfPane(t.root, _LeafTab('א')), isNull);
    });
  });

  group('prunePanes', () {
    test('מסירה חלונית שנדחתה ומקריסה את הצומת שהתרוקן', () {
      final t = _nestedTree();
      final pruned = prunePanes(t.root, (pane) => pane.title != 'ב');

      expect(paneCount(pruned!), 2);
      expect(paneAt(pruned, const [kFirstPane]), same(t.a));
      expect(paneAt(pruned, const [kSecondPane]), same(t.c));
    });

    test('עץ שכולו נדחה מוחזר כ-null', () {
      final t = _nestedTree();
      expect(prunePanes(t.root, (_) => false), isNull);
    });

    test('עלה בודד שנדחה מוחזר כ-null, ושהתקבל מוחזר כמות שהוא', () {
      final leaf = _LeafTab('א');
      expect(prunePanes(leaf, (_) => false), isNull);
      expect(prunePanes(leaf, (_) => true), same(leaf));
    });

    test('עץ שלא השתנה מוחזר כאובייקט המקורי', () {
      final t = _nestedTree();
      expect(prunePanes(t.root, (_) => true), same(t.root));
    });

    test('גיזום עמוק שומר על זהות החלוניות שנשארו', () {
      final a = _LeafTab('א');
      final b = _LeafTab('ב');
      final c = _LeafTab('ג');
      final d = _LeafTab('ד');
      final root = CombinedTab(
        rightTab: CombinedTab(rightTab: a, leftTab: b),
        leftTab: CombinedTab(rightTab: c, leftTab: d),
      );

      final pruned = prunePanes(root, (pane) => pane.title != 'ג')!;
      expect(leafPanes(pruned), [same(a), same(b), same(d)]);
    });
  });

  group('serialization', () {
    test('הלוך-ושוב משמר מבנה, ציר ויחס', () {
      final t = _nestedTree();
      t.root.splitRatio = 0.35;
      (paneAt(t.root, const [kSecondPane]) as CombinedTab).splitRatio = 0.6;

      // עלי הבדיקה אינם ניתנים לשחזור, ולכן נבדק עץ מקונן של טאבי חיפוש
      // דרך המבנה בלבד: הציר והיחס הם מה שנוסף כאן.
      final json = t.root.toJson();
      expect(json['axis'], 'horizontal');
      expect(json['splitRatio'], 0.35);
      expect((json['leftTab'] as Map)['axis'], 'vertical');
      expect((json['leftTab'] as Map)['splitRatio'], 0.6);
      expect((json['leftTab'] as Map)['type'], 'CombinedTab');
    });

    test('ציר חסר בנתונים ישנים נקרא כאופקי', () {
      expect(SplitAxis.fromId(null), SplitAxis.horizontal);
      expect(SplitAxis.fromId('horizontal'), SplitAxis.horizontal);
      expect(SplitAxis.fromId('vertical'), SplitAxis.vertical);
      expect(SplitAxis.fromId('גיבוב'), SplitAxis.horizontal);
    });
  });

  group('הצמדה', () {
    test('פיצול חלונית מוצמדת משאיר את הטאב מוצמד', () {
      final pinned = _LeafTab('מוצמד')..isPinned = true;

      final root = splitPaneAt(
        pinned,
        const [],
        _LeafTab('חדש'),
        position: PaneDropPosition.end,
      );

      // בלי זה "סגור הכל" היה סוגר כרטיסיה שהמשתמש נעץ.
      expect(root.isPinned, isTrue);
    });

    test('פיצול חלונית שאינה מוצמדת אינו מצמיד', () {
      final root = splitPaneAt(
        _LeafTab('רגיל'),
        const [],
        _LeafTab('חדש'),
        position: PaneDropPosition.bottom,
      );

      expect(root.isPinned, isFalse);
    });

    test('סגירת חלונית מעבירה את ההצמדה לאחות שנשארה', () {
      final survivor = _LeafTab('נשארת');
      final root = CombinedTab(rightTab: _LeafTab('נסגרת'), leftTab: survivor)
        ..isPinned = true;

      final remaining = removePaneAt(root, const [kFirstPane]);

      expect(remaining, same(survivor));
      expect(remaining!.isPinned, isTrue);
    });

    test('סגירת חלונית בטאב שאינו מוצמד אינה מצמידה', () {
      final survivor = _LeafTab('נשארת');
      final root = CombinedTab(rightTab: _LeafTab('נסגרת'), leftTab: survivor);

      expect(removePaneAt(root, const [kFirstPane])!.isPinned, isFalse);
    });
  });

  group('כותרת', () {
    test('נבנית מכל העלים ולא מכותרות מקוננות', () {
      final t = _nestedTree();
      expect(t.root.title, 'משולב: א | ב | ג');
    });

    test('מתעדכנת כשכותרת חלונית משתנה אחרי הבנייה', () {
      final t = _nestedTree();
      // ספר טוען את כותרתו אחרי הפתיחה; כותרת שהוקפאה בבנייה נשארה מיושנת
      // ב-tooltip וברשימת הקיצורים של Windows.
      t.b.title = 'ב מעודכן';

      expect(t.root.title, 'משולב: א | ב מעודכן | ג');
    });

    test('מתעדכנת אחרי שינוי מבנה', () {
      final t = _nestedTree();
      final result =
          splitPaneAt(
                t.root,
                const [kFirstPane],
                _LeafTab('ד'),
                position: PaneDropPosition.end,
              )
              as CombinedTab;
      expect(result.title, 'משולב: א | ד | ב | ג');
    });
  });
}
