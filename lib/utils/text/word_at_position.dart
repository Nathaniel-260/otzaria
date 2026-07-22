import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// תוצאת זיהוי מילה תחת הסמן: המילה עצמה, והאם היא בתוך span אינטראקטיבי
/// (קישור/עוגן עם recognizer או מאזיני ריחוף).
typedef WordHit = ({String word, bool isInteractive});

/// מחזיר את המילה שנמצאת תחת הסמן בנקודה גלובלית נתונה.
///
/// משתמש ב-hit-testing על ה-render tree כדי למצוא את ה-[RenderParagraph]
/// הרלוונטי, ואז שולף את גבולות המילה דרך [RenderParagraph.getWordBoundary].
///
/// מחזיר null אם לא נמצאה מילה (לחיצה על אזור ריק, תמונה, וכו').
String? wordAtGlobalPosition(Offset globalPosition) {
  return wordHitAtGlobalPosition(globalPosition)?.word;
}

/// כמו [wordAtGlobalPosition], אך מחזיר גם האם המילה יושבת בתוך span
/// אינטראקטיבי — כדי שריחוף-מילה לא יתחרה בתצוגה המקדימה של קישור.
WordHit? wordHitAtGlobalPosition(Offset globalPosition) {
  final hitTestResult = BoxHitTestResult();
  for (final view in WidgetsBinding.instance.renderViews) {
    view.hitTest(hitTestResult, position: globalPosition);
  }

  for (final entry in hitTestResult.path) {
    final target = entry.target;
    if (target is! RenderParagraph) continue;
    try {
      final localPosition = target.globalToLocal(globalPosition);
      final textPosition = target.getPositionForOffset(localPosition);
      final wordRange = target.getWordBoundary(textPosition);
      if (wordRange.isCollapsed) continue;
      final plainText = target.text.toPlainText();
      if (wordRange.start < 0 || wordRange.end > plainText.length) continue;
      final word = plainText.substring(wordRange.start, wordRange.end).trim();
      if (word.isEmpty) continue;
      return (
        word: word,
        isInteractive: _isInteractiveAt(target.text, wordRange.start),
      );
    } catch (_) {
      continue;
    }
  }
  return null;
}

/// בודק אם ההיסט [offset] בטקסט השטוח נמצא בתוך span עם recognizer או
/// מאזיני עכבר (כולל spans אב שהעיצוב שלהם עוטף את הילדים).
bool _isInteractiveAt(InlineSpan root, int offset) {
  var cursor = 0;
  var found = false;

  void visit(InlineSpan span) {
    final start = cursor;
    if (span is TextSpan) {
      if (span.text != null) cursor += span.text!.length;
      span.children?.forEach(visit);
      final within = offset >= start && offset < cursor;
      if (within &&
          (span.recognizer != null ||
              span.onEnter != null ||
              span.onExit != null)) {
        found = true;
      }
    } else {
      // PlaceholderSpan נספר כתו אחד (U+FFFC) בטקסט השטוח.
      cursor += 1;
    }
  }

  visit(root);
  return found;
}
