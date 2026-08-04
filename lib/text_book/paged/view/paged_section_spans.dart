import 'package:flutter/material.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show isHeadingLine;
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// תקרת המטמון. עמוד גלוי נוגע בעשרות סעיפים, ושלושה עמודים בונים הרבה פחות
/// ממאתיים וחמישים ושש.
const int _maxCachedSpans = 256;

/// בונה את הספאן של סעיף לתצוגת העמודים.
///
/// **אותו מופע חייב לשרת גם את העימוד וגם את הציור.** העימוד מדד את הספאן הזה
/// בדיוק, וכל הבדל בטקסט או במטריקות בין המדידה לציור יחתוך שורות בתחתית העמוד.
/// היחיד שמותר להוסיף בציור הוא רקע שורה נבחרת — צבע רקע אינו משנה מטריקות.
class PagedSectionSpanBuilder {
  final List<String> content;
  final RenderSettings settings;
  final TextStyle baseStyle;

  PagedSectionSpanBuilder({
    required this.content,
    required this.settings,
    required this.baseStyle,
  });

  /// סגנון השורש של כל הספאנים בתצוגה.
  ///
  /// הצבע מפורש בכוונה: הציור עובר דרך `RichText`, שאינו יורש `DefaultTextStyle`
  /// מהעץ, וספאן בלי צבע נצבע בלבן — ברירת המחדל של מנוע הטקסט.
  static TextStyle baseStyleFor(
    RenderSettings settings,
    ColorScheme colorScheme,
  ) => TextStyle(
    color: colorScheme.onSurface,
    fontSize: settings.fontSize,
    fontFamily: settings.fontFamily,
    fontWeight: settings.fontWeight,
    height: settings.lineHeight,
  );

  final Map<int, InlineSpan?> _cache = {};

  /// מספר הבניות שבוצעו בפועל — לאימות שהמטמון פוגע.
  @visibleForTesting
  int buildCount = 0;

  InlineSpan? spanFor(int index) {
    if (index < 0 || index >= content.length) return null;

    // בדיקת הימצאות לפני ההסרה — סעיף ריק ממוזכר כ-null, ובלי הבדיקה הוא היה
    // נבנה מחדש בכל קריאה.
    if (_cache.containsKey(index)) {
      final cached = _cache.remove(index);
      _cache[index] = cached;
      return cached;
    }

    final span = _build(index);
    buildCount++;
    if (_cache.length >= _maxCachedSpans) _cache.remove(_cache.keys.first);
    _cache[index] = span;
    return span;
  }

  InlineSpan? _build(int index) {
    final raw = content[index].trim();
    if (raw.isEmpty) return null;

    final html = TextRendererService.processText(raw, settings);
    final spans = buildInlineHtmlSpans(
      html,
      baseStyle,
      applyBlockStyles: true,
    );
    if (spans.isEmpty) return null;
    return TextSpan(style: baseStyle, children: spans);
  }

  /// סעיף שהוא כותרת. העימוד שומר עליו שלא יישבר ושלא יישאר לבד בתחתית טור.
  bool isHeading(int index) =>
      index >= 0 && index < content.length && isHeadingLine(content[index]);

  void clear() {
    _cache.clear();
    buildCount = 0;
  }
}
