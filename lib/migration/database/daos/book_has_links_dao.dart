import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import '../../models/book.dart';
import '../sqlite3_utils.dart';
import '../query_loader.dart';
import 'database.dart';

// Simple model for book_has_links table entries
class BookHasLinksEntry {
  final int bookId;
  final bool hasSourceLinks;
  final bool hasTargetLinks;

  const BookHasLinksEntry({
    required this.bookId,
    required this.hasSourceLinks,
    required this.hasTargetLinks,
  });

  factory BookHasLinksEntry.fromMap(Map<String, dynamic> map) {
    return BookHasLinksEntry(
      bookId: map['bookId'] as int,
      hasSourceLinks: (map['hasSourceLinks'] as int) == 1,
      hasTargetLinks: (map['hasTargetLinks'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bookId': bookId,
      'hasSourceLinks': hasSourceLinks ? 1 : 0,
      'hasTargetLinks': hasTargetLinks ? 1 : 0,
    };
  }
}

class BookHasLinksDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  BookHasLinksDao(this._db) {
    _queries = QueryLoader.loadQueries('BookHasLinksQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<List<Book>> getBooksWithSourceLinks() async {
    final db = await database;
    return db
        .select(_queries['selectBooksWithSourceLinks']!)
        .toMapList()
        .map((row) => Book.fromJson(row))
        .toList();
  }

  Future<List<Book>> getBooksWithTargetLinks() async {
    final db = await database;
    return db
        .select(_queries['selectBooksWithTargetLinks']!)
        .toMapList()
        .map((row) => Book.fromJson(row))
        .toList();
  }

  Future<List<Book>> getBooksWithAnyLinks() async {
    final db = await database;
    return db
        .select(_queries['selectBooksWithAnyLinks']!)
        .toMapList()
        .map((row) => Book.fromJson(row))
        .toList();
  }

  Future<int> countBooksWithSourceLinks() async {
    final db = await database;
    return firstIntValue(db.select(_queries['countBooksWithSourceLinks']!)) ??
        0;
  }

  Future<int> countBooksWithTargetLinks() async {
    final db = await database;
    return firstIntValue(db.select(_queries['countBooksWithTargetLinks']!)) ??
        0;
  }

  Future<int> countBooksWithAnyLinks() async {
    final db = await database;
    return firstIntValue(db.select(_queries['countBooksWithAnyLinks']!)) ?? 0;
  }

  Future<int> updateSourceLinks(int bookId, bool hasSourceLinks) async {
    final db = await database;
    db.execute(_queries['updateSourceLinks']!, [
      hasSourceLinks ? 1 : 0,
      bookId,
    ]);
    return db.updatedRows;
  }

  Future<int> updateTargetLinks(int bookId, bool hasTargetLinks) async {
    final db = await database;
    db.execute(_queries['updateTargetLinks']!, [
      hasTargetLinks ? 1 : 0,
      bookId,
    ]);
    return db.updatedRows;
  }

  Future<int> updateBothLinkTypes(
    int bookId,
    bool hasSourceLinks,
    bool hasTargetLinks,
  ) async {
    final db = await database;
    db.execute(_queries['updateBothLinkTypes']!, [
      hasSourceLinks ? 1 : 0,
      hasTargetLinks ? 1 : 0,
      bookId,
    ]);
    return db.updatedRows;
  }

}
