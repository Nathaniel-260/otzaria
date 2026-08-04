import 'dart:convert';
import 'dart:typed_data';

import 'package:otzaria/text_book/paged/models/page_geometry.dart';
import 'package:otzaria/text_book/paged/models/paginated_book.dart';

/// גרסת פורמט הסדרוול. שינוי בפריסת הבייטים חייב להעלות אותה, כדי שרשומות
/// ישנות ייפסלו במקום להיקרא שגוי.
const int kPaginatedBookCodecVersion = 1;

/// מספר השלמים לכל פרוסה: סעיף, התחלה, סוף, דגלים.
const int _intsPerSlice = 4;

const int _flagContinuesPrevious = 1;
const int _flagContinuesNext = 2;

/// מסדרל ספר מעומד ל-base64 של שלמים בני 32 ביט.
///
/// ספר גדול מכיל עשרות אלפי פרוסות; פורמט טקסטואלי היה שוקל מגה-בייטים
/// ומצריך פירסור לכל פתיחה. הגאומטריה אינה נשמרת כאן — היא חלק ממפתח המטמון,
/// ולכן מגיעה מהקורא.
String encodePaginatedBook(PaginatedBook book) {
  var intCount = 3;
  for (final page in book.pages) {
    intCount += 3;
    for (final column in page.columns) {
      intCount += 1 + column.slices.length * _intsPerSlice;
    }
  }

  final data = ByteData(intCount * 4);
  var offset = 0;
  void put(int value) {
    // setInt32 קוטם בשקט מחוץ לטווח, וספר מקודד היה יוצא פגום בלי שנדע.
    assert(
      value >= -2147483648 && value <= 2147483647,
      'ערך מחוץ לטווח int32: $value',
    );
    data.setInt32(offset, value, Endian.little);
    offset += 4;
  }

  put(kPaginatedBookCodecVersion);
  put(book.sectionCount);
  put(book.pages.length);
  for (var pageIndex = 0; pageIndex < book.pages.length; pageIndex++) {
    final page = book.pages[pageIndex];
    // מספר העמוד אינו מקודד — הפענוח גוזר אותו מהמקום ברשימה. מספור אחר
    // (למשל לפי דפי הדפוס) יידרש להוסיף אותו לזרם.
    assert(
      page.number == pageIndex + 1,
      'מספר העמוד אינו נגזר מהמקום ברשימה',
    );
    put(page.firstSourceIndex);
    put(page.lastSourceIndex);
    put(page.columns.length);
    for (final column in page.columns) {
      put(column.slices.length);
      for (final slice in column.slices) {
        put(slice.sourceIndex);
        put(slice.charStart);
        put(slice.charEnd);
        put(
          (slice.continuesPrevious ? _flagContinuesPrevious : 0) |
              (slice.continuesNext ? _flagContinuesNext : 0),
        );
      }
    }
  }

  return base64Encode(data.buffer.asUint8List());
}

/// מפענח ספר מעומד. מחזיר null לכל קלט שאינו תקין — הנתונים באים מקובץ
/// מטמון שיכול להישאר מגרסה ישנה או להיפגם.
PaginatedBook? decodePaginatedBook(String encoded, PageGeometry geometry) {
  final reader = _Int32Reader.tryParse(encoded);
  if (reader == null) return null;

  try {
    if (reader.next() != kPaginatedBookCodecVersion) return null;
    final sectionCount = reader.next();
    // כל עמוד תופס לפחות שלושה שלמים: סעיף ראשון, אחרון ומספר טורים.
    final pageCount = reader.count(intsEach: 3);
    if (sectionCount < 0) return null;

    final pages = <BookPage>[];
    for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      final first = reader.next();
      final last = reader.next();
      // אינדקסים מחוץ לטווח היו מפוענחים לספר "תקין" שבו הניווט מגיע לעמוד
      // שרירותי ופרוסות נעלמות בשקט. עדיף לעמד מחדש מלהציג עימוד שגוי.
      if (first < 0 || last < first || last >= sectionCount) return null;
      final columnCount = reader.count();

      final columns = <PageColumn>[];
      for (var c = 0; c < columnCount; c++) {
        final sliceCount = reader.count(intsEach: _intsPerSlice);
        final slices = <PageSlice>[];
        for (var s = 0; s < sliceCount; s++) {
          final sourceIndex = reader.next();
          final charStart = reader.next();
          final charEnd = reader.next();
          final flags = reader.next();
          if (sourceIndex < 0 ||
              sourceIndex >= sectionCount ||
              charStart < 0 ||
              charEnd < charStart) {
            return null;
          }
          slices.add(
            PageSlice(
              sourceIndex: sourceIndex,
              charStart: charStart,
              charEnd: charEnd,
              continuesPrevious: flags & _flagContinuesPrevious != 0,
              continuesNext: flags & _flagContinuesNext != 0,
            ),
          );
        }
        columns.add(PageColumn(List.unmodifiable(slices)));
      }

      pages.add(
        BookPage(
          number: pageIndex + 1,
          columns: List.unmodifiable(columns),
          firstSourceIndex: first,
          lastSourceIndex: last,
        ),
      );
    }

    // זנב שלא נקרא מסמן שהקידוד אינו זה שהפענוח מצפה לו.
    if (!reader.isAtEnd) return null;

    return PaginatedBook(
      pages: List.unmodifiable(pages),
      geometry: geometry,
      sectionCount: sectionCount,
    );
  } on _MalformedLayout {
    return null;
  }
}

class _MalformedLayout implements Exception {
  const _MalformedLayout();
}

class _Int32Reader {
  final ByteData _data;
  final int _length;
  int _offset = 0;

  _Int32Reader(this._data) : _length = _data.lengthInBytes;

  static _Int32Reader? tryParse(String encoded) {
    Uint8List bytes;
    try {
      bytes = base64Decode(encoded);
    } catch (_) {
      return null;
    }
    if (bytes.length < 12 || bytes.length % 4 != 0) return null;
    return _Int32Reader(ByteData.sublistView(bytes));
  }

  int get _remainingInts => (_length - _offset) ~/ 4;

  bool get isAtEnd => _offset >= _length;

  int next() {
    if (_offset + 4 > _length) throw const _MalformedLayout();
    final value = _data.getInt32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  /// קורא מונה ומאמת שיש בזרם מקום לפריטים שהוא מבטיח. בלי האימות הזה מונה
  /// פגום היה גורם להקצאת רשימה עצומה לפני שהקריאה נכשלת.
  int count({int intsEach = 1}) {
    final value = next();
    if (value < 0 || value > _remainingInts ~/ intsEach) {
      throw const _MalformedLayout();
    }
    return value;
  }
}
