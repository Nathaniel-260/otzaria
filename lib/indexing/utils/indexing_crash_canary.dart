import 'dart:convert';
import 'dart:io';

/// ספר שנשאר באמצע אינדוקס כשהתהליך מת, פעמיים ברצף.
class IndexingCrashedBefore implements Exception {
  const IndexingCrashedBefore();

  @override
  String toString() => 'אינדוקס הספר הפיל את התוכנה פעמיים ברצף; הספר דולג';
}

/// הספרים שבאמצע אינדוקס, בקובץ שנותר רק כשהתהליך מת באמצע הריצה.
class IndexingCrashCanary {
  IndexingCrashCanary._(this._file) : _attempts = _read(_file);

  /// הריצה הפעילה; סגירה מסודרת של התוכנה מסיימת אותה ([finish]).
  static IndexingCrashCanary? current;

  static void start(String? indexPath) => current = indexPath == null
      ? null
      : IndexingCrashCanary._(File('$indexPath.in_flight.json'));

  static const maxAttempts = 2;

  final File _file;
  final Map<String, int> _attempts;
  final Set<String> _inFlight = {};
  RandomAccessFile? _raf;

  /// ריצה קודמת מתה באמצע: מאנדקסים ספר-ספר, כדי שרק האשם ייספר.
  bool get recovering => _attempts.isNotEmpty;

  static Map<String, int> _read(File file) {
    try {
      return Map<String, int>.from(jsonDecode(file.readAsStringSync()) as Map);
    } catch (_) {
      return {};
    }
  }

  /// false לספר שכבר הפיל [maxAttempts] ריצות; המונה שלו מתאפס.
  bool begin(String key) {
    final attempts = _attempts[key] ?? 0;
    if (attempts >= maxAttempts) {
      end(key);
      return false;
    }
    if (_inFlight.add(key)) {
      _attempts[key] = attempts + 1;
      _write();
    }
    return true;
  }

  void end(String key) {
    _inFlight.remove(key);
    if (_attempts.remove(key) != null) _write();
  }

  /// הריצה הסתיימה (או התוכנה נסגרה) בלי שהתהליך מת — מה שבטיסה לא הפיל אותו.
  void finish() {
    if (identical(current, this)) current = null;
    _inFlight.toList().forEach(end);
    try {
      _raf?.closeSync();
    } catch (_) {}
  }

  // קובץ פתוח לאורך הריצה: פתיחה לכל כתיבה עלתה פי 10 (נמדד ב-Windows).
  void _write() {
    try {
      final bytes = utf8.encode(jsonEncode(_attempts));
      (_raf ??= _file.openSync(mode: FileMode.write))
        ..setPositionSync(0)
        ..writeFromSync(bytes)
        ..truncateSync(bytes.length);
    } catch (_) {}
  }
}
