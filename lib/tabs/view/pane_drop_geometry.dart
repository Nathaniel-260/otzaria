import 'dart:ui';

import 'package:otzaria/tabs/models/pane_tree.dart';

/// חלקה של החלונית (מכל קצה) שנחשב אזור פיצול. השאר הוא אזור המרכז.
const double kPaneDropEdgeFraction = 0.28;

/// המקום המזערי שחייב להישאר לכל חלונית — גם בפיצול וגם בגרירת מפריד.
const double kMinPaneExtent = 140;

/// מחשבת לאיזה אזור הפלה שייך [localPosition] בתוך חלונית בגודל [size].
///
/// גבולות האזורים אלכסוניים: נבחר הקצה הקרוב ביותר למצביע, ורק אם המצביע
/// קרוב אליו יותר מ-[edgeFraction]. כך פינה מפצלת לפי הקצה שאליו התכוונו
/// ולא לפי סדר בדיקה שרירותי.
///
/// ציר שבו הפיצול היה מותיר חלונית קטנה מ-[minPaneExtent] אינו מוצע כלל:
/// בלי זה פיצול חוזר במסך צר היה מייצר חלוניות ברוחב בלתי קריא, ובלי דרך
/// חזרה מהן.
PaneDropPosition dropPositionFor({
  required Offset localPosition,
  required Size size,
  required TextDirection textDirection,
  double edgeFraction = kPaneDropEdgeFraction,
  double minPaneExtent = kMinPaneExtent,
}) {
  if (size.width <= 0 || size.height <= 0) return PaneDropPosition.center;

  final x = (localPosition.dx / size.width).clamp(0.0, 1.0);
  final y = (localPosition.dy / size.height).clamp(0.0, 1.0);

  final distances = <PaneDropPosition, double>{
    if (size.width >= minPaneExtent * 2) ...{
      _leadingEdge(textDirection): x,
      _trailingEdge(textDirection): 1 - x,
    },
    if (size.height >= minPaneExtent * 2) ...{
      PaneDropPosition.top: y,
      PaneDropPosition.bottom: 1 - y,
    },
  };
  if (distances.isEmpty) return PaneDropPosition.center;

  var closest = PaneDropPosition.top;
  var minDistance = double.infinity;
  for (final entry in distances.entries) {
    if (entry.value < minDistance) {
      minDistance = entry.value;
      closest = entry.key;
    }
  }

  return minDistance <= edgeFraction ? closest : PaneDropPosition.center;
}

/// המלבן שהחלונית הנגררת תתפוס בחלונית בגודל [size] — הבסיס לחיווי הוויזואלי.
Rect previewRectFor({
  required PaneDropPosition position,
  required Size size,
  required TextDirection textDirection,
}) {
  final full = Offset.zero & size;
  return switch (position) {
    PaneDropPosition.center => full,
    PaneDropPosition.top => Rect.fromLTWH(0, 0, size.width, size.height / 2),
    PaneDropPosition.bottom => Rect.fromLTWH(
      0,
      size.height / 2,
      size.width,
      size.height / 2,
    ),
    PaneDropPosition.start || PaneDropPosition.end => _horizontalPreview(
      position,
      size,
      textDirection,
    ),
  };
}

Rect _horizontalPreview(
  PaneDropPosition position,
  Size size,
  TextDirection textDirection,
) {
  final onLeft = position == _leadingEdge(textDirection);
  return Rect.fromLTWH(
    onLeft ? 0 : size.width / 2,
    0,
    size.width / 2,
    size.height,
  );
}

/// אזור ההפלה הצמוד לקצה השמאלי של המסך.
PaneDropPosition _leadingEdge(TextDirection textDirection) =>
    textDirection == TextDirection.rtl
    ? PaneDropPosition.end
    : PaneDropPosition.start;

/// אזור ההפלה הצמוד לקצה הימני של המסך.
PaneDropPosition _trailingEdge(TextDirection textDirection) =>
    textDirection == TextDirection.rtl
    ? PaneDropPosition.start
    : PaneDropPosition.end;
