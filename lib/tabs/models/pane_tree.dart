import 'package:flutter/foundation.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// נתיב לחלונית בעץ הפיצולים של טאב.
///
/// כל צעד הוא `0` (החלונית הראשונה — ימנית/עליונה) או `1` (השנייה —
/// שמאלית/תחתונה). נתיב ריק מציין את שורש הטאב.
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

  // הצומת יורש הצמדה מכל חלונית שהייתה מוצמדת: צומת חדש שאינו מוצמד היה
  // מבטל בשקט את ההצמדה, ו"סגור הכל" היה סוגר את הכרטיסיה שהמשתמש נעץ.
  final isPinned = target.isPinned || incoming.isPinned;
  final split = position.placesIncomingFirst
      ? CombinedTab(
          rightTab: incoming,
          leftTab: target,
          axis: axis,
          splitRatio: ratio,
          isPinned: isPinned,
        )
      : CombinedTab(
          rightTab: target,
          leftTab: incoming,
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

/// כל חלוניות העלה, בסדר התצוגה.
List<OpenedTab> leafPanes(OpenedTab root) {
  final leaves = <OpenedTab>[];
  void walk(OpenedTab node) {
    if (node is CombinedTab) {
      walk(node.rightTab);
      walk(node.leftTab);
    } else {
      leaves.add(node);
    }
  }

  walk(root);
  return leaves;
}

/// מספר חלוניות העלה בטאב. `1` לטאב שאינו מפוצל.
int paneCount(OpenedTab root) => leafPanes(root).length;

/// מסירה מהעץ כל חלונית עלה ש-[keep] דוחה, ומקריסה צמתים שהתרוקנו.
///
/// מחזירה `null` אם לא נותרה אף חלונית. עץ שלא השתנה מוחזר כאובייקט
/// המקורי, כדי לא לאבד את זהות החלוניות שנשמרו.
OpenedTab? prunePanes(OpenedTab root, bool Function(OpenedTab pane) keep) {
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

/// תוצאת הפלת חלונית על עץ.
@immutable
class PaneDropResult {
  /// שורש העץ אחרי ההפלה.
  final OpenedTab root;

  /// חלונית שנדחקה מהעץ ואין לה מקום — על הקורא להחליט אם לסגור אותה
  /// או להחזירה לשורת הכרטיסיות. `null` כשלא נדחקה אף חלונית.
  final OpenedTab? displaced;

  const PaneDropResult({required this.root, this.displaced});
}

/// מחילה הפלה של [incoming] על החלונית ב-[targetPath].
///
/// [sourcePath] הוא מקום החלונית הנגררת באותו עץ, כשהגרירה פנימית. הפלה
/// פנימית במרכז מחליפה בין שתי החלוניות במקומן; הפלה פנימית על קצה מזיזה
/// את החלונית ומקריסה את הצומת שהתרוקן. הפלה חיצונית במרכז דוחקת את
/// החלונית הקיימת ומחזירה אותה ב-[PaneDropResult.displaced].
///
/// זורקת [ArgumentError] אם אחד הנתיבים אינו תקין.
PaneDropResult applyPaneDrop({
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

  if (sourcePath == null) {
    if (position == PaneDropPosition.center) {
      return PaneDropResult(
        root: replacePaneAt(root, targetPath, incoming),
        displaced: target,
      );
    }
    return PaneDropResult(
      root: splitPaneAt(
        root,
        targetPath,
        incoming,
        position: position,
        ratio: ratio,
      ),
    );
  }

  final source = paneAt(root, sourcePath);
  if (source == null) {
    throw ArgumentError.value(sourcePath, 'sourcePath', 'נתיב חלונית לא תקין');
  }

  // הזזה אל תוך עצמה אינה מוגדרת — היעד היה נעלם יחד עם המקור שהוסר.
  if (identical(source, target) || pathOfPane(source, target) != null) {
    return PaneDropResult(root: root);
  }

  if (position == PaneDropPosition.center) {
    final swappedSource = replacePaneAt(root, sourcePath, target);
    return PaneDropResult(
      root: replacePaneAt(swappedSource, targetPath, source),
    );
  }

  // ההסרה קודמת לפיצול, ולכן נתיב היעד מאותר מחדש לפי זהות האובייקט —
  // הסרת החלונית עשויה להקריס צומת ולקצר את הנתיב.
  final afterRemove = removePaneAt(root, sourcePath);
  if (afterRemove == null) return PaneDropResult(root: root);

  final updatedTargetPath = pathOfPane(afterRemove, target);
  if (updatedTargetPath == null) return PaneDropResult(root: root);

  return PaneDropResult(
    root: splitPaneAt(
      afterRemove,
      updatedTargetPath,
      incoming,
      position: position,
      ratio: ratio,
    ),
  );
}

/// הנתיב אל [target] בתוך [root] לפי זהות אובייקט, או `null` אם אינו שם.
PanePath? pathOfPane(OpenedTab root, OpenedTab target) {
  PanePath? walk(OpenedTab node, PanePath path) {
    if (identical(node, target)) return path;
    if (node is CombinedTab) {
      return walk(node.rightTab, [...path, kFirstPane]) ??
          walk(node.leftTab, [...path, kSecondPane]);
    }
    return null;
  }

  return walk(root, <int>[]);
}
