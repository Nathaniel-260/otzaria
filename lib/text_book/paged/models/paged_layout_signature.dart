import 'package:flutter/material.dart';
import 'package:otzaria/text_book/paged/models/page_geometry.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

/// גרסת מנוע העימוד. כל שינוי באלגוריתם השבירה או בקבועים המוצמדים למטה
/// חייב להעלות אותה, אחרת עימוד שנשמר במטמון יוצג עם חוקי שבירה אחרים.
const int kPagedLayoutEngineVersion = 1;

/// `TextWidthBasis` מוצמד: המדידה והציור תמיד ברוחב טור מדויק, ולכן הבסיס
/// אינו משנה שבירה או גובה. אינו שדה בחתימה — שינוי כאן דורש העלאת
/// [kPagedLayoutEngineVersion].
const TextWidthBasis kPagedTextWidthBasis = TextWidthBasis.parent;

/// כל מה שקובע איפה שורה נשברת ומה גובהה.
///
/// שתי אי-התאמות אפשריות שהחתימה מגנה מפניהן: תוכן שהוחלף מתחת לעימוד שמור,
/// וסביבת מדידה שהשתנתה (גופן, זום מערכת, גאומטריה). [cacheKey] הוא המפתח
/// שבו העימוד נשמר.
///
/// **התוכן חייב להיות טעון במלואו.** רשימת תוכן עם מקומות שמורים ריקים תיתן
/// טביעת אצבע של טקסט חלקי, ולכן העימוד יישמר תחת מפתח שלא יימצא שוב.
@immutable
class PagedLayoutSignature {
  /// זהות הספר — כותרת הספר, כפי שהיא משמשת בשאר המטמונים.
  final String bookId;

  final int lineCount;

  /// סך התווים בכל השורות.
  final int charCount;
  final int contentHash;

  final PageGeometry geometry;

  final double fontSize;
  final String? fontFamily;

  /// `FontWeight.value`, או null לברירת המחדל.
  final int? fontWeight;
  final double lineHeight;

  /// הסקיילר של מערכת ההפעלה, נמדד **על גודל הגופן שבשימוש**. סקיילר לא-לינארי
  /// מחזיר 1.0 עבור 1.0 ובכל זאת מגדיל גדלים אמיתיים, ולכן מדידה על 1.0 לא
  /// הייתה מבדילה בינו לבין סקיילר מנוטרל.
  final double textScale;

  /// תגית ה-locale שבה הטקסט עובר shaping.
  final String localeTag;

  // ---- טרנספורמציות תוכן: משנות את הטקסט עצמו לפני המדידה ----
  final bool removeNikud;
  final bool removeTeamim;
  final bool removePunctuation;
  final bool replaceHolyNames;
  final bool formatParentheses;
  final bool justifyText;

  /// קישורי inline מזריקים סמני-אות לטקסט, ולכן משנים את רוחב השורה.
  final bool enableInlineLinks;

  /// [AppFonts.fontMetricsTag] של הגופן — מצב הרישום שלו בזמן המדידה.
  final String fontMetricsTag;

  final int engineVersion;

  const PagedLayoutSignature({
    required this.bookId,
    required this.lineCount,
    required this.charCount,
    required this.contentHash,
    required this.geometry,
    required this.fontSize,
    required this.fontFamily,
    required this.fontWeight,
    required this.lineHeight,
    required this.textScale,
    required this.localeTag,
    required this.removeNikud,
    required this.removeTeamim,
    required this.removePunctuation,
    required this.replaceHolyNames,
    required this.formatParentheses,
    required this.justifyText,
    required this.enableInlineLinks,
    required this.fontMetricsTag,
    this.engineVersion = kPagedLayoutEngineVersion,
  });

  /// בונה חתימה מתוך ההגדרות החיות.
  ///
  /// כל שדה שנוסף ל-[RenderSettings] ומשפיע על פריסה חייב להתווסף גם כאן;
  /// `paged_layout_signature_test` נכשל אם שדה כזה אינו משנה את המפתח.
  factory PagedLayoutSignature.from({
    required String bookId,
    required List<String> content,
    required PageGeometry geometry,
    required RenderSettings settings,
    required TextScaler textScaler,
    required Locale locale,
  }) {
    var chars = 0;
    for (final line in content) {
      chars += line.length;
    }

    return PagedLayoutSignature(
      bookId: bookId,
      lineCount: content.length,
      charCount: chars,
      contentHash: Object.hashAll(content),
      geometry: geometry,
      fontSize: settings.fontSize,
      fontFamily: settings.fontFamily,
      fontWeight: settings.fontWeight?.value,
      lineHeight: settings.lineHeight,
      textScale: textScaler.scale(settings.fontSize),
      localeTag: locale.toLanguageTag(),
      removeNikud: settings.removeNikud,
      removeTeamim: settings.removeTeamim,
      removePunctuation: settings.removePunctuation,
      replaceHolyNames: settings.replaceHolyNames,
      formatParentheses: settings.formatParentheses,
      justifyText: settings.justifyText,
      enableInlineLinks: settings.enableInlineLinks,
      fontMetricsTag: AppFonts.fontMetricsTag(settings.fontFamily),
    );
  }

  /// דגלי התוכן כמחרוזת ביטים — קצר ויציב יותר מרשימת `true/false`.
  String get _flags => [
    removeNikud,
    removeTeamim,
    removePunctuation,
    replaceHolyNames,
    formatParentheses,
    justifyText,
    enableInlineLinks,
  ].map((flag) => flag ? '1' : '0').join();

  /// המפתח שתחתיו העימוד נשמר במטמון.
  String get cacheKey =>
      'v$engineVersion|$bookId|'
      'n$lineCount,c$charCount,h$contentHash|'
      '${geometry.cacheKey}|'
      'fs${fontSize.toStringAsFixed(2)},'
      'ff${fontFamily ?? '-'},'
      'fw${fontWeight ?? '-'},'
      'lh${lineHeight.toStringAsFixed(3)},'
      'ts${textScale.toStringAsFixed(3)},'
      'lc$localeTag|'
      '$_flags|'
      'fm$fontMetricsTag';

  @override
  bool operator ==(Object other) =>
      other is PagedLayoutSignature && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;

  @override
  String toString() => 'PagedLayoutSignature($cacheKey)';
}
