import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;

import '../../models/paged_layout_cache_entry.dart';
import '../sql/query_loader.dart';
import '../sql/sqlite3_utils.dart';
import 'database.dart';

/// DAO למטמון העימוד של תצוגת העמודים (טבלת `paged_layout_cache`, מאוכלסת
/// ב-`cache.db`). מקביל ל-[DocxTextCacheDao].
class PagedLayoutCacheDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  PagedLayoutCacheDao(this._db) {
    _queries = QueryLoader.loadQueries('PagedLayoutCacheQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<PagedLayoutCacheEntry?> selectByKey(String layoutKey) async {
    final db = await database;
    final result = db.select(_queries['selectByKey']!, [
      layoutKey,
    ]).toMapList();
    if (result.isEmpty) return null;
    return PagedLayoutCacheEntry.fromMap(result.first);
  }

  Future<void> upsert(PagedLayoutCacheEntry entry) async {
    final db = await database;
    db.execute(_queries['upsert']!, [
      entry.layoutKey,
      entry.bookTitle,
      entry.pageCount,
      entry.layout,
      entry.createdAt,
      entry.accessedAt,
    ]);
  }

  Future<void> updateAccessedAt(String layoutKey, int accessedAt) async {
    final db = await database;
    db.execute(_queries['updateAccessedAt']!, [accessedAt, layoutKey]);
  }

  Future<void> deleteByBookTitle(String bookTitle) async {
    final db = await database;
    db.execute(_queries['deleteByBookTitle']!, [bookTitle]);
  }

  Future<void> deleteAccessedBefore(int cutoffMillis) async {
    final db = await database;
    db.execute(_queries['deleteAccessedBefore']!, [cutoffMillis]);
  }
}
