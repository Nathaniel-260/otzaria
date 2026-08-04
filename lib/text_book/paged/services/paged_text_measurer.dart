import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectionRegistrar;
import 'package:otzaria/text_book/paged/models/page_geometry.dart';
import 'package:otzaria/text_book/paged/models/paged_layout_signature.dart';

/// תוצאת מדידה של פסקה אחת ברוחב טור נתון.
///
/// שומרת מספרים בלבד — לא `TextPainter` ולא `Paragraph`. ספר שלם מכיל מאות
/// אלפי שורות חזותיות, והחזקת אובייקטי פריסה חיים עבורן מפילה את התהליך.
@immutable
class MeasuredParagraph {
  /// היסט אנכי של ראש כל שורה, ובאיבר האחרון גובה הפסקה כולה.
  /// אורכה `lineCount + 1`.
  final List<double> lineOffsets;

  /// היסט התו הראשון בכל שורה חזותית.
  final List<int> lineStarts;

  /// היסט התו שאחרי סוף כל שורה חזותית, **בלי** תו שורה חדשה שמפריד לשורה
  /// הבאה. חיתוך לפי הערך הזה מונע שורה ריקה בסוף הפרוסה.
  final List<int> lineEnds;

  const MeasuredParagraph({
    required this.lineOffsets,
    required this.lineStarts,
    required this.lineEnds,
  });

  static const MeasuredParagraph empty = MeasuredParagraph(
    lineOffsets: [0],
    lineStarts: [],
    lineEnds: [],
  );

  int get lineCount => lineStarts.length;

  double get totalHeight => lineOffsets.last;

  bool get isEmpty => lineCount == 0;

  /// גובה [count] השורות הראשונות.
  double heightOfFirst(int count) => lineOffsets[count.clamp(0, lineCount)];

  /// גובה השורות [from] ועד סוף הפסקה.
  double heightFrom(int from) =>
      totalHeight - lineOffsets[from.clamp(0, lineCount)];

  /// כמה שורות שלמות, מהשורה [from], נכנסות בגובה [available].
  ///
  /// חיפוש בינארי על ההיסטים המצטברים. מחזיר 0 כשגם שורה אחת לא נכנסת —
  /// זה הסימן שצריך לפתוח עמוד חדש.
  int linesFittingFrom(int from, double available) {
    if (available <= 0 || from >= lineCount) return 0;
    final ceiling = lineOffsets[from] + available;
    var low = from;
    var high = lineCount;
    while (low < high) {
      final mid = low + (high - low + 1) ~/ 2;
      if (lineOffsets[mid] > ceiling) {
        high = mid - 1;
      } else {
        low = mid;
      }
    }
    return low - from;
  }
}

/// מודד גבהים ושבירת שורות של פסקאות ברוחב טור קבוע.
///
/// הפרמטרים כאן חייבים להיות זהים לאלה שהתצוגה מציירת בהם. `textWidthBasis`
/// מוצמד ל-[kPagedTextWidthBasis], ו-`strutStyle` נשאר null — האפליקציה אינה
/// משתמשת ב-strut, ו-strut במדידה בלבד היה מקצר כותרות.
class PagedTextMeasurer {
  final double width;
  final TextScaler textScaler;
  final Locale locale;
  final TextAlign textAlign;
  final TextDirection textDirection;

  const PagedTextMeasurer({
    required this.width,
    required this.textScaler,
    required this.locale,
    this.textAlign = TextAlign.justify,
    this.textDirection = TextDirection.rtl,
  });

  /// המודד לגאומטריה נתונה. נוסחה אחת שגם העימוד וגם הציור נגזרים ממנה — שני
  /// מקומות שמחשבים את רוחב הטור בנפרד היו יכולים להיפרד זה מזה.
  factory PagedTextMeasurer.forGeometry({
    required PageGeometry geometry,
    required TextScaler textScaler,
    required Locale locale,
    required bool justifyText,
  }) {
    return PagedTextMeasurer(
      width: geometry.columnWidth,
      textScaler: textScaler,
      locale: locale,
      textAlign: justifyText ? TextAlign.justify : TextAlign.start,
    );
  }

  /// בונה את הווידג'ט שמצייר [span] בדיוק כפי ש-[measure] מדד אותו.
  ///
  /// **חובה לצייר דרך כאן ולא דרך `Text`/`Text.rich`.** `Text` עוטף את הספאן
  /// ב-`DefaultTextStyle` של העץ, ובתוך `Material` יש בו `letterSpacing: 0.25`
  /// שהמדידה אינה רואה — השורות נשברות מוקדם יותר בציור, וכל טור מאבד שורה
  /// בתחתיתו. `RichText` מקבל את הספאן כמו שהוא, בלי ירושה.
  ///
  /// [selectionRegistrar] ו-[selectionColor] הם מה ש-`Text` היה מחבר לבד; בלעדיהם
  /// בחירת טקסט ב-`SelectionArea` לא עובדת.
  Widget buildText(
    InlineSpan span, {
    SelectionRegistrar? selectionRegistrar,
    Color? selectionColor,
  }) {
    return RichText(
      text: span,
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
      textWidthBasis: kPagedTextWidthBasis,
      selectionRegistrar: selectionRegistrar,
      selectionColor: selectionColor,
    );
  }

  /// מודד פסקה. מחזיר null כשלא ניתן למדוד אותה בבטחה — ראו
  /// [spanHasPlaceholder] ואת בדיקת העקביות בסוף.
  MeasuredParagraph? measure(InlineSpan span) {
    if (spanHasPlaceholder(span)) return null;

    final text = span.toPlainText(includeSemanticsLabels: false);
    if (text.isEmpty) return MeasuredParagraph.empty;

    final painter = TextPainter(
      text: span,
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
      textWidthBasis: kPagedTextWidthBasis,
    );
    try {
      painter.layout(minWidth: width, maxWidth: width);
      return _extract(painter, text);
    } finally {
      painter.dispose();
    }
  }

  MeasuredParagraph? _extract(TextPainter painter, String text) {
    final metrics = painter.computeLineMetrics();
    if (metrics.isEmpty) return MeasuredParagraph.empty;

    final starts = <int>[];
    final ends = <int>[];
    final length = text.length;
    var cursor = 0;

    while (cursor < length) {
      final range = painter.getLineBoundary(TextPosition(offset: cursor));
      // שורה חזותית ריקה (שני שוברי שורה רצופים) מחזירה טווח באורך אפס, והיא
      // אכן ריקה — קידום מלאכותי כאן היה מכניס את השובר לתוך סוף השורה,
      // ופרוסה שנחתכת שם הייתה מציירת שורה ריקה נוספת.
      final end = range.end > cursor ? range.end : cursor;
      starts.add(cursor);
      // כשהשובר הוא התו האחרון בטקסט, getLineBoundary מכליל אותו בטווח.
      // הקיצוץ מוגבל לאורך הטווח, אחרת שורה ריקה הייתה מקצצת את זו שלפניה.
      final trailing = math.min(lineBreakLengthBefore(text, end), end - cursor);
      ends.add(end - trailing);

      final following = lineBreakLengthAt(text, end);
      if (following > 0) {
        cursor = end + following;
      } else if (end > cursor) {
        cursor = end;
      } else {
        // הגבול אינו מתקדם ואין שובר שורה לדלג עליו. עדיף לא למדוד מלמדוד שגוי.
        return null;
      }
    }

    // טקסט שמסתיים בשובר שורה מייצר שורה חזותית ריקה נוספת.
    if (lineBreakLengthBefore(text, length) > 0) {
      starts.add(length);
      ends.add(length);
    }

    // הגבולות והמטריקות חייבים להיות באותו אורך, אחרת גובה שורה אחת יוצמד
    // לטווח של שורה אחרת. מוותרים על מדידת הפסקה במקום לעמד אותה שגוי.
    if (starts.length != metrics.length) return null;

    final offsets = List<double>.filled(metrics.length + 1, 0);
    for (var i = 0; i < metrics.length; i++) {
      offsets[i + 1] = offsets[i] + metrics[i].height;
    }

    return MeasuredParagraph(
      lineOffsets: offsets,
      lineStarts: starts,
      lineEnds: ends,
    );
  }
}

/// אורך שובר השורה שמתחיל ב-[index], או 0 אם אין שם שובר.
///
/// לא רק `\n`: מנוע הטקסט שובר שורה גם ב-CR, VT, FF, NEL, וב-U+2028/2029 —
/// ואלה מגיעים מטקסט שמקורו ב-HTML או ב-JSON. התעלמות מהם החזירה מדידה כשלה,
/// והסעיף כולו נדחס לפרוסה אחת שנחתכה בגובה הטור.
int lineBreakLengthAt(String text, int index) {
  if (index < 0 || index >= text.length) return 0;
  final code = text.codeUnitAt(index);
  if (code == 0x0D) {
    final isCrLf =
        index + 1 < text.length && text.codeUnitAt(index + 1) == 0x0A;
    return isCrLf ? 2 : 1;
  }
  return _isSingleUnitLineBreak(code) ? 1 : 0;
}

/// אורך שובר השורה שנגמר ב-[index] (כלומר מסתיים בתו שלפניו), או 0.
int lineBreakLengthBefore(String text, int index) {
  if (index <= 0 || index > text.length) return 0;
  final code = text.codeUnitAt(index - 1);
  if (code == 0x0A) {
    final isCrLf = index >= 2 && text.codeUnitAt(index - 2) == 0x0D;
    return isCrLf ? 2 : 1;
  }
  if (code == 0x0D) return 1;
  return _isSingleUnitLineBreak(code) ? 1 : 0;
}

bool _isSingleUnitLineBreak(int code) =>
    code == 0x0A ||
    code == 0x0B ||
    code == 0x0C ||
    code == 0x85 ||
    code == 0x2028 ||
    code == 0x2029;

/// האם הספאן מכיל `WidgetSpan`/placeholder. פריסה של ספאן כזה דורשת
/// `setPlaceholderDimensions` מראש, ולכן הוא אינו נמדד כטקסט.
bool spanHasPlaceholder(InlineSpan span) {
  var found = false;
  span.visitChildren((child) {
    if (child is PlaceholderSpan) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// חותך [span] לטווח התווים `[start, end)` של הטקסט השטוח שלו, ומשמר סגנון,
/// recognizer ואירועי ריחוף.
///
/// בטוח לחיתוך בגבול שורה חזותית: שבירת השורות ב-Flutter חמדנית ומשמאל לימין
/// לוגית, ולכן קידומת שנגמרת בגבול שורה נשברת בדיוק כמו במקור, וכך גם השארית.
/// חיתוך **באמצע** שורה אינו מובטח.
InlineSpan? sliceInlineSpan(InlineSpan span, int start, int end) {
  if (end <= start) return null;
  return _SpanSlicer(start, end).slice(span);
}

class _SpanSlicer {
  final int start;
  final int end;
  int _offset = 0;

  _SpanSlicer(this.start, this.end);

  /// חייב לרדת על כל תת-העץ גם כשהוא מחוץ לטווח — היציאה מוקדם הייתה משאירה
  /// את [_offset] מפגר, וכל החיתוך היה מוסט.
  InlineSpan? slice(InlineSpan span) {
    if (span is! TextSpan) {
      // placeholder תופס תו אחד בטקסט השטוח.
      final at = _offset;
      _offset++;
      return (at >= start && at < end) ? span : null;
    }

    String? slicedText;
    final text = span.text;
    if (text != null && text.isNotEmpty) {
      final spanStart = _offset;
      final spanEnd = _offset + text.length;
      final from = start > spanStart ? start : spanStart;
      final to = end < spanEnd ? end : spanEnd;
      if (to > from) {
        slicedText = text.substring(from - spanStart, to - spanStart);
      }
      _offset = spanEnd;
    }

    final children = span.children;
    List<InlineSpan>? slicedChildren;
    if (children != null) {
      for (final child in children) {
        final sliced = slice(child);
        if (sliced != null) (slicedChildren ??= <InlineSpan>[]).add(sliced);
      }
    }

    if (slicedText == null && slicedChildren == null) return null;

    return TextSpan(
      text: slicedText,
      children: slicedChildren,
      style: span.style,
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }
}
