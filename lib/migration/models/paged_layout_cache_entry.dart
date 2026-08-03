/// רשומת מטמון מתמשך לעימוד ספר לעמודים פיזיים (תצוגת "עמוד קבוע").
///
/// העימוד יקר: הוא מודד כל שורה חזותית בספר, ומדידת טקסט אפשרית רק ב-isolate
/// הראשי. ספר גדול לוקח שניות, ולכן התוצאה נשמרת ב-`cache.db` (כתיב).
///
/// [layoutKey] הוא `PagedLayoutSignature.cacheKey` — הוא כבר מכיל את זהות
/// התוכן, הגאומטריה, סגנון הטקסט וגרסת המנוע, ולכן אין כאן שדות תוקף נוספים:
/// כל שינוי שמשפיע על פריסה מייצר מפתח אחר.
class PagedLayoutCacheEntry {
  final String layoutKey;

  /// כותרת הספר. מאפשרת למחוק בבת אחת את כל וריאנטי העימוד של ספר שהשתנה.
  final String bookTitle;

  final int pageCount;

  /// פלט [encodePaginatedBook].
  final String layout;

  final int createdAt;
  final int accessedAt;

  const PagedLayoutCacheEntry({
    required this.layoutKey,
    required this.bookTitle,
    required this.pageCount,
    required this.layout,
    required this.createdAt,
    required this.accessedAt,
  });

  factory PagedLayoutCacheEntry.fromMap(Map<String, dynamic> map) {
    return PagedLayoutCacheEntry(
      layoutKey: map['layoutKey'] as String,
      bookTitle: map['bookTitle'] as String? ?? '',
      pageCount: map['pageCount'] as int? ?? 0,
      layout: map['layout'] as String? ?? '',
      createdAt: map['createdAt'] as int? ?? 0,
      accessedAt: map['accessedAt'] as int? ?? 0,
    );
  }

  @override
  String toString() =>
      'PagedLayoutCacheEntry(book: $bookTitle, pages: $pageCount, '
      'key: $layoutKey)';
}
