import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import '../query_loader.dart';
import '../sqlite3_utils.dart';
import 'database.dart';

// Simple model for connection type table entries
class ConnectionTypeEntry {
  final int id;
  final String name;

  const ConnectionTypeEntry({
    required this.id,
    required this.name,
  });

  factory ConnectionTypeEntry.fromMap(Map<String, dynamic> map) {
    return ConnectionTypeEntry(
      id: map['id'] as int,
      name: map['name'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }
}

class ConnectionTypeDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  ConnectionTypeDao(this._db) {
    _queries = QueryLoader.loadQueries('ConnectionTypeQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  Future<List<ConnectionTypeEntry>> getAllConnectionTypes() async {
    final db = await database;
    return db
        .select(_queries['selectAll']!)
        .toMapList()
        .map((row) => ConnectionTypeEntry.fromMap(row))
        .toList();
  }

}
