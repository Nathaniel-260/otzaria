import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pane_group_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// נתיב לחלונית בעץ הפיצולים של טאב.
///
/// כל צעד הוא `0` (החלונית הראשונה — ימנית/עליונה) או `1` (השנייה —
/// שמאלית/תחתונה). נתיב ריק מציין את שורש הטאב.
///
/// הנתיב מצביע על חלונית, לא על כרטיסייה שבתוכה: [PaneGroupTab] הוא עלה
/// לכל דבר, והכרטיסיות שבו מזוהות לפי אובייקט.
typedef PanePath = List<int>;

/// אינדקס החלונית הראשונה בצומת פיצול.
const int kFirstPane = 0;

/// אינדקס החלונית השנייה בצומת פיצול.
const int kSecondPane = 1;

/// מיקום ההפלה של חלונית נגררת יחסית לחלונית היעד.
enum PaneDropPosition {
  /// החלפת תוכן חלונית היעד — ללא פיצול.
  center,

  /// פיצול אופקי; הנגררת נכנסת בקצה ההתחלתי (ימין ב-RTL).
  start,

  /// פיצול אופקי; הנגררת נכנסת בקצה הסופי (שמאל ב-RTL).
  end,

  /// פיצול אנכי; הנגררת נכנסת למעלה.
  top,

  /// פיצול אנכי; הנגררת נכנסת למטה.
  bottom;

  /// ציר הפיצול שהמיקום מייצר. `null` עבור [center], שאינו מפצל.
  SplitAxis? get axis => switch (this) {
    center => null,
    start || end => SplitAxis.horizontal,
    top || bottom => SplitAxis.vertical,
  };

  /// האם החלונית הנגררת תופסת את המקום הראשון בצומת החדש.
  bool get placesIncomingFirst => this == start || this == top;
}

/// מחזירה את החלונית בנתיב [path], או `null` אם הנתיב אינו תקין
/// (חורג מהטווח או יורד אל תוך חלונית עלה).
OpenedTab? paneAt(OpenedTab root, PanePath path) {
  var node = root;
  for (final step in path) {
    if (node is! CombinedTab) return null;
    if (step == kFirstPane) {
      node = node.rightTab;
    } else if (step == kSecondPane) {
      node = node.leftTab;
    } else {
      return null;
    }
  }
  return node;
}

/// האם [path] מצביע על חלונית קיימת בעץ.
bool isValidPanePath(OpenedTab root, PanePath path) =>
    paneAt(root, path) != null;

/// מחזירה עץ שבו החלונית ב-[path] הוחלפה ב-[replacement].
///
/// כל חלונית שאינה על הנתיב מוחזרת כאובייקט המקורי עצמו — שימור ה-identity
/// הזה הוא מה שמאפשר ל-`GlobalObjectKey` לשמר את ה-State של חלוניות שלא
/// נגעו בהן כשמבנה העץ משתנה.
///
/// זורקת [ArgumentError] אם [path] אינו תקין.
OpenedTab replacePaneAt(
  OpenedTab root,
  PanePath path,
  OpenedTab replacement,
) {
  if (path.isEmpty) return replacement;

  final node = root;
  if (node is! CombinedTab) {
    throw ArgumentError.value(path, 'path', 'הנתיב יורד אל תוך חלונית עלה');
  }

  final step = path.first;
  final rest = path.sublist(1);
  if (step == kFirstPane) {
    return node.copyWith(
      rightTab: replacePaneAt(node.rightTab, rest, replacement),
    );
  }
  if (step == kSecondPane) {
    return node.copyWith(
      leftTab: replacePaneAt(node.leftTab, rest, replacement),
    );
  }
  throw ArgumentError.value(path, 'path', 'צעד לא חוקי בנתיב: $step');
}

/// מפצלת את החלונית ב-[path]: היא ו-[incoming] הופכות לצמד תחת צומת חדש.
///
/// [position] קובע את הציר ואת הצד שבו נכנסת [incoming]. הפלה במרכז
/// ([PaneDropPosition.center]) אינה מפצלת אלא מחליפה את תוכן החלונית.
///
/// [incoming] חייבת להיות חלונית שאינה כבר בעץ: הפונקציה מוסיפה בלבד,
/// וחלונית שתופיע פעמיים תייצר מפתח כפול ותפיל את הרינדור. להזזה בתוך
/// אותו עץ יש להשתמש ב-[applyPaneDrop] עם `sourcePath`.
///
/// זורקת [ArgumentError] אם [path] אינו תקין.
OpenedTab splitPaneAt(
  OpenedTab root,
  PanePath path,
  OpenedTab incoming, {
  required PaneDropPosition position,
  double ratio = 0.5,
}) {
  final target = paneAt(root, path);
  if (target == null) {
    throw ArgumentError.value(path, 'path', 'נתיב חלונית לא תקין');
  }

  final axis = position.axis;
  if (axis == null) return replacePaneAt(root, path, incoming);

  // כל צד בפיצול הוא חלונית עם רצועת כרטיסיות משלה, ולכן שתיהן נעטפות.
  final targetPane = PaneGroupTab.wrap(target);
  final incomingPane = PaneGroupTab.wrap(incoming);

  // הצומת יורש הצמדה מכל חלונית שהייתה מוצמדת: צומת חדש שאינו מוצמד היה
  // מבטל בשקט את ההצמדה, ו"סגור הכל" היה סוגר את הכרטיסיה שהמשתמש נעץ.
  final isPinned = target.isPinned || incoming.isPinned;
  final split = position.placesIncomingFirst
      ? CombinedTab(
          rightTab: incomingPane,
          leftTab: targetPane,
          axis: axis,
          splitRatio: ratio,
          isPinned: isPinned,
        )
      : CombinedTab(
          rightTab: targetPane,
          leftTab: incomingPane,
          axis: axis,
          splitRatio: ratio,
          isPinned: isPinned,
        );

  return replacePaneAt(root, path, split);
}

/// מסירה את החלונית ב-[path]; אחותה תופסת את מקום צומת האב.
///
/// מחזירה `null` כשהוסר השורש עצמו (נתיב ריק) — כלומר הטאב כולו נסגר.
/// זורקת [ArgumentError] אם [path] אינו תקין.
OpenedTab? removePaneAt(OpenedTab root, PanePath path) {
  if (path.isEmpty) return null;

  final parentPath = path.sublist(0, path.length - 1);
  final parent = paneAt(root, parentPath);
  if (parent is! CombinedTab) {
    throw ArgumentError.value(path, 'path', 'נתיב חלונית לא תקין');
  }

  final step = path.last;
  final OpenedTab sibling;
  if (step == kFirstPane) {
    sibling = parent.leftTab;
  } else if (step == kSecondPane) {
    sibling = parent.rightTab;
  } else {
    throw ArgumentError.value(path, 'path', 'צעד לא חוקי בנתיב: $step');
  }

  // האחות תופסת את מקום ההורה וגם את הצמדתו — אחרת סגירת חלונית הייתה
  // מבטלת בשקט הצמדה שהמשתמש קבע.
  if (parent.isPinned) sibling.isPinned = true;

  return replacePaneAt(root, parentPath, sibling);
}

/// מחליפה בין שתי החלוניות של צומת הפיצול ב-[path], כולל היפוך היחס.
///
/// זורקת [ArgumentError] אם [path] אינו מצביע על צומת פיצול.
OpenedTab swapPanesAt(OpenedTab root, PanePath path) {
  final node = paneAt(root, path);
  if (node is! CombinedTab) {
    throw ArgumentError.value(path, 'path', 'הנתיב אינו מצביע על צומת פיצול');
  }

  final swapped = CombinedTab(
    rightTab: node.leftTab,
    leftTab: node.rightTab,
    axis: node.axis,
    splitRatio: 1.0 - node.splitRatio,
    isPinned: node.isPinned,
  );
  return replacePaneAt(root, path, swapped);
}

/// הנתיבים לכל חלוניות העלה, בסדר התצוגה.
List<PanePath> leafPanePaths(OpenedTab root) {
  final paths = <PanePath>[];
  void walk(OpenedTab node, PanePath path) {
    if (node is CombinedTab) {
      walk(node.rightTab, [...path, kFirstPane]);
      walk(node.leftTab, [...path, kSecondPane]);
    } else {
      paths.add(path);
    }
  }

  // רשימה חדשה ולא `const []`: הנתיבים המוחזרים ניתנים לשינוי בידי הקורא.
  walk(root, <int>[]);
  return paths;
}

/// חלוניות העלה עצמן — קבוצות כרטיסיות, בסדר התצוגה.
///
/// זו החלוקה הגאומטרית של הטאב. לרשימת הספרים שבתוכן ראו [leafPanes].
List<OpenedTab> panesOf(OpenedTab root) {
  final panes = <OpenedTab>[];
  void walk(OpenedTab node) {
    if (node is CombinedTab) {
      walk(node.rightTab);
      walk(node.leftTab);
    } else {
      panes.add(node);
    }
  }

  walk(root);
  return panes;
}

/// כל הכרטיסיות שבטאב, בסדר התצוגה — כולל אלו שמוסתרות מאחורי כרטיסייה
/// אחרת באותה חלונית.
///
/// זו הרשימה שמעניינת כל מי ששואל "אילו ספרים פתוחים": היסטוריה, איתור טאב
/// קיים, תקציב זיכרון. למי ששואל "כמה תיבות מוצגות" יש [panesOf].
List<OpenedTab> leafPanes(OpenedTab root) {
  final leaves = <OpenedTab>[];
  for (final pane in panesOf(root)) {
    if (pane is PaneGroupTab) {
      leaves.addAll(pane.tabs);
    } else {
      leaves.add(pane);
    }
  }
  return leaves;
}

/// הכרטיסיות הנראות בפועל — אחת לכל חלונית.
List<OpenedTab> visiblePaneTabs(OpenedTab root) => [
  for (final pane in panesOf(root))
    if (pane is PaneGroupTab) pane.activeTab else pane,
];

/// מספר חלוניות העלה בטאב. `1` לטאב שאינו מפוצל.
int paneCount(OpenedTab root) => panesOf(root).length;

/// החלונית המחזיקה את [tab], או `null` אם אינו בעץ.
OpenedTab? paneContaining(OpenedTab root, OpenedTab tab) {
  for (final pane in panesOf(root)) {
    if (identical(pane, tab)) return pane;
    if (pane is PaneGroupTab && pane.tabs.any((t) => identical(t, tab))) {
      return pane;
    }
  }
  return null;
}

/// פורקת קבוצה שנותרה בשורש הטאב.
///
/// לשורש אין רצועת כרטיסיות משלו — שורת הכרטיסיות של החלון היא הרצועה שלו —
/// ולכן הכרטיסייה המוצגת נשארת כטאב, והשאר מוחזרות לקורא כדי שיכניס אותן
/// לשורה. עץ שאינו קבוצה מוחזר כמות שהוא.
({OpenedTab root, List<OpenedTab> released}) unwrapRootGroup(OpenedTab root) {
  if (root is! PaneGroupTab) return (root: root, released: const []);
  final kept = root.activeTab;
  kept.isPinned = kept.isPinned || root.isPinned;
  return (
    root: kept,
    released: [
      for (final tab in root.tabs)
        if (!identical(tab, kept)) tab,
    ],
  );
}

/// מסירה מהעץ כל כרטיסייה ש-[keep] דוחה, ומקריסה חלוניות וצמתים שהתרוקנו.
///
/// מחזירה `null` אם לא נותרה אף כרטיסייה. עץ שלא השתנה מוחזר כאובייקט
/// המקורי, כדי לא לאבד את זהות החלוניות שנשמרו.
OpenedTab? prunePanes(OpenedTab root, bool Function(OpenedTab pane) keep) {
  if (root is PaneGroupTab) {
    final kept = root.tabs.where(keep).toList();
    if (kept.isEmpty) return null;
    if (kept.length == root.tabs.length) return root;
    // חלונית חדשה ולא שינוי במקום: הגיזום רץ גם על עץ חי בדרך לשמירה,
    // ושם הסרת כרטיסייה הייתה מעלימה אותה מהמסך.
    final activeIndex = kept.indexWhere(
      (tab) => identical(tab, root.activeTab),
    );
    return PaneGroupTab(
      tabs: kept,
      activeIndex: activeIndex == -1 ? 0 : activeIndex,
      isPinned: root.isPinned,
    );
  }
  if (root is! CombinedTab) return keep(root) ? root : null;

  final first = prunePanes(root.rightTab, keep);
  final second = prunePanes(root.leftTab, keep);
  if (first == null) return second;
  if (second == null) return first;
  if (identical(first, root.rightTab) && identical(second, root.leftTab)) {
    return root;
  }
  return root.copyWith(rightTab: first, leftTab: second);
}

/// מחילה הפלה של הכרטיסייה [incoming] על החלונית ב-[targetPath], ומחזירה
/// את שורש העץ החדש — או `null` כשההפלה לא שינתה דבר.
///
/// הפלה במרכז מוסיפה את הכרטיסייה לרצועת החלונית; הפלה על קצה מפצלת אותה
/// לשתיים. [sourcePath] הוא החלונית שממנה נגררה הכרטיסייה, כשהגרירה פנימית —
/// אז היא מוסרת משם, וחלונית שהתרוקנה נסגרת.
///
/// זורקת [ArgumentError] אם אחד הנתיבים אינו תקין.
OpenedTab? applyPaneDrop({
  required OpenedTab root,
  required OpenedTab incoming,
  required PanePath targetPath,
  required PaneDropPosition position,
  PanePath? sourcePath,
  double ratio = 0.5,
}) {
  final target = paneAt(root, targetPath);
  if (target == null) {
    throw ArgumentError.value(targetPath, 'targetPath', 'נתיב חלונית לא תקין');
  }

  var tree = root;
  if (sourcePath != null) {
    final source = paneAt(tree, sourcePath);
    if (source == null) {
      throw ArgumentError.value(
        sourcePath,
        'sourcePath',
        'נתיב חלונית לא תקין',
      );
    }
    // הכרטיסייה כבר במקומה: הפלה במרכז חלוניתה שלה אינה משנה דבר, וגרירת
    // הכרטיסייה היחידה אל קצה חלוניתה הייתה מפצלת חלונית אל תוך עצמה.
    if (identical(source, target) &&
        (position == PaneDropPosition.center ||
            source is! PaneGroupTab ||
            source.tabs.length <= 1)) {
      return null;
    }
    // נבדק לפני כל שינוי: אחרי הסרת הכרטיסייה מהמקור אין דרך חזרה.
    if (position == PaneDropPosition.center && target is! PaneGroupTab) {
      return null;
    }

    final removed = source is PaneGroupTab && source.removeTab(incoming);
    if (!removed) {
      // חלונית שנשארה בלי כרטיסיות נסגרת, ונתיב היעד מאותר מחדש לפי זהות —
      // הסגירה מקריסה את צומת האב ומקצרת נתיבים.
      final afterRemove = removePaneAt(tree, sourcePath);
      if (afterRemove == null) return null;
      tree = afterRemove;
    }
  }

  final updatedTargetPath = pathOfPane(tree, target);
  if (updatedTargetPath == null) return null;

  if (position == PaneDropPosition.center) {
    final pane = paneAt(tree, updatedTargetPath);
    // רק חלונית בתוך פיצול מחזיקה רצועת כרטיסיות; בשורש הרצועה היא שורת
    // הכרטיסיות של החלון, והכרטיסייה כבר שם.
    if (pane is! PaneGroupTab) return null;
    pane.addTab(incoming);
    return tree;
  }

  return splitPaneAt(
    tree,
    updatedTargetPath,
    incoming,
    position: position,
    ratio: ratio,
  );
}

/// הנתיב אל [target] בתוך [root] לפי זהות אובייקט, או `null` אם אינו שם.
///
/// כרטיסייה שיושבת בתוך חלונית מקבלת את נתיב החלונית שלה — נתיבים מצביעים
/// על חלוניות בלבד.
PanePath? pathOfPane(OpenedTab root, OpenedTab target) {
  PanePath? walk(OpenedTab node, PanePath path) {
    if (identical(node, target)) return path;
    if (node is CombinedTab) {
      return walk(node.rightTab, [...path, kFirstPane]) ??
          walk(node.leftTab, [...path, kSecondPane]);
    }
    if (node is PaneGroupTab && node.tabs.any((t) => identical(t, target))) {
      return path;
    }
    return null;
  }

  return walk(root, <int>[]);
}
