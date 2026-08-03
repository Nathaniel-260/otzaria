import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/paged_layout_cache_entry.dart';
import 'package:otzaria/text_book/paged/models/paged_layout_signature.dart';
import 'package:otzaria/text_book/paged/models/paginated_book.dart';
import 'package:otzaria/text_book/paged/repository/paginated_book_codec.dart';

/// כמה זמן רשומת עימוד שלא נגעו בה נשמרת. שינוי גופן או גודל חלון מייצר
/// וריאנט חדש, והישן נמחק אחרי חודש של אי-שימוש.
const Duration _layoutTtl = Duration(days: 30);

/// עדכון זמן הגישה לכל היותר פעם ביום — מונע כתיבת WAL בכל פתיחת ספר.
const int _touchThrottleMs = 24 * 60 * 60 * 1000;

/// מטמון מתמשך לעימוד תצוגת העמודים, ב-`cache.db`.
///
/// כל הפעולות best-effort: מטמון שאינו נגיש מחזיר "אין רשומה", והספר יעומד
/// מחדש. כשל כאן לעולם אינו מונע מהמשתמש לקרוא.
class PagedLayoutCache {
  PagedLayoutCache({Future<SeforimRepository> Function()? repositoryProvider})
    : _repositoryProvider = repositoryProvider ?? _defaultRepository;

  static Future<SeforimRepository> _defaultRepository() =>
      CacheDatabaseHolder.instance.repository;

  static final PagedLayoutCache shared = PagedLayoutCache();

  final Future<SeforimRepository> Function() _repositoryProvider;

  /// העימוד השמור ל-[signature], או null כשאין כזה או שאינו תקין.
  Future<PaginatedBook?> load(PagedLayoutSignature signature) async {
    try {
      final repository = await _repositoryProvider();
      final entry = await repository.getPagedLayoutCacheEntry(
        signature.cacheKey,
      );
      if (entry == null) return null;

      final book = decodePaginatedBook(entry.layout, signature.geometry);
      // מספר הסעיפים חייב להתאים לחתימה. אי-התאמה = רשומה פגומה, ועימוד
      // שמפנה לסעיפים שאינם קיימים היה מציג עמודים ריקים.
      if (book == null || book.sectionCount != signature.lineCount) return null;

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - entry.accessedAt > _touchThrottleMs) {
        unawaited(
          repository
              .touchPagedLayoutCacheEntry(signature.cacheKey, now)
              .catchError((_) {}),
        );
      }
      return book;
    } catch (e) {
      debugPrint('⚠️ paged layout cache read failed: $e');
      return null;
    }
  }

  Future<void> save(
    PagedLayoutSignature signature,
    PaginatedBook book,
  ) async {
    try {
      final repository = await _repositoryProvider();
      final now = DateTime.now().millisecondsSinceEpoch;
      await repository.upsertPagedLayoutCacheEntry(
        PagedLayoutCacheEntry(
          layoutKey: signature.cacheKey,
          bookTitle: signature.bookId,
          pageCount: book.pageCount,
          layout: encodePaginatedBook(book),
          createdAt: now,
          accessedAt: now,
        ),
      );
      await repository.prunePagedLayoutCacheAccessedBefore(
        now - _layoutTtl.inMilliseconds,
      );
    } catch (e) {
      debugPrint('⚠️ paged layout cache write failed: $e');
    }
  }

  /// מוחק את כל וריאנטי העימוד של ספר. נדרש כשתוכן הספר נערך: החתימה תופס
  /// ממילא, אבל הרשומות הישנות היו נשארות ותופסות מקום עד ה-TTL.
  Future<void> invalidateBook(String bookTitle) async {
    try {
      final repository = await _repositoryProvider();
      await repository.deletePagedLayoutCacheForBook(bookTitle);
    } catch (e) {
      debugPrint('⚠️ paged layout cache invalidate failed: $e');
    }
  }
}
