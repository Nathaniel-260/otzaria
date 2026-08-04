import 'package:flutter/foundation.dart';
import 'package:otzaria/text_book/paged/models/page_geometry.dart';

/// חלק מסעיף מקור אחד, כפי שהוא מוצג בטור אחד.
///
/// [charStart] ו-[charEnd] הם היסטים בטקסט השטוח של הספאן שנבנה מהסעיף —
/// בדיוק הקלט של `sliceInlineSpan`. הם נחתכים תמיד בגבול שורה חזותית.
@immutable
class PageSlice {
  /// אינדקס הסעיף ב-`content` של הספר.
  final int sourceIndex;
  final int charStart;
  final int charEnd;

  /// הסעיף התחיל בטור קודם.
  final bool continuesPrevious;

  /// הסעיף נמשך בטור הבא.
  ///
  /// גם הכלל לציור: מרווח בין-סעיפים מתווסף רק אחרי פרוסה שהדגל הזה כבוי בה,
  /// כי כך העימוד חישב אותו. תוספת מרווח אחרי פרוסת המשך תדחוף שורה מהתחתית.
  final bool continuesNext;

  const PageSlice({
    required this.sourceIndex,
    required this.charStart,
    required this.charEnd,
    this.continuesPrevious = false,
    this.continuesNext = false,
  });

  bool get isEmpty => charEnd <= charStart;

  @override
  bool operator ==(Object other) =>
      other is PageSlice &&
      other.sourceIndex == sourceIndex &&
      other.charStart == charStart &&
      other.charEnd == charEnd &&
      other.continuesPrevious == continuesPrevious &&
      other.continuesNext == continuesNext;

  @override
  int get hashCode => Object.hash(
    sourceIndex,
    charStart,
    charEnd,
    continuesPrevious,
    continuesNext,
  );

  @override
  String toString() =>
      'PageSlice($sourceIndex, $charStart..$charEnd'
      '${continuesPrevious ? ', ←' : ''}${continuesNext ? ', →' : ''})';
}

/// טור אחד בעמוד.
@immutable
class PageColumn {
  final List<PageSlice> slices;

  const PageColumn(this.slices);

  static const PageColumn empty = PageColumn([]);

  bool get isEmpty => slices.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is PageColumn && listEquals(other.slices, slices);

  @override
  int get hashCode => Object.hashAll(slices);
}

/// רצועה אופקית בעמוד.
///
/// העמוד אינו שני טורים מלמעלה למטה אלא רצועות זו מעל זו: כותרת פורשת על כל
/// רוחב העמוד, ורצועת הגוף שאחריה מתחלקת לטורים מחדש.
sealed class PageBand {
  const PageBand();

  Iterable<PageSlice> get slices;

  bool get isEmpty;

  /// המרווח האנכי שלפני [band]. **העימוד והציור חייבים לקרוא לכאן שניהם** —
  /// שני חישובים נפרדים היו נפרדים זה מזה ודוחפים שורה מתחתית העמוד.
  static double gapBefore(
    PageBand band,
    PageBand? previous,
    PageGeometry geometry,
  ) {
    if (previous == null) return 0;
    // אין רווח בין כותרת לגוף שמתחתיה — הם יחידה אחת.
    if (band is! HeadingBand) return 0;
    return previous is HeadingBand ? geometry.sectionGap : geometry.headingGap;
  }
}

/// כותרת על כל רוחב העמוד. אינה נשברת בין עמודים.
final class HeadingBand extends PageBand {
  final PageSlice slice;

  const HeadingBand(this.slice);

  @override
  Iterable<PageSlice> get slices => [slice];

  @override
  bool get isEmpty => slice.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is HeadingBand && other.slice == slice;

  @override
  int get hashCode => slice.hashCode;
}

/// גוף בטורים.
final class ColumnsBand extends PageBand {
  final List<PageColumn> columns;

  const ColumnsBand(this.columns);

  @override
  Iterable<PageSlice> get slices => columns.expand((column) => column.slices);

  @override
  bool get isEmpty => columns.every((column) => column.isEmpty);

  @override
  bool operator ==(Object other) =>
      other is ColumnsBand && listEquals(other.columns, columns);

  @override
  int get hashCode => Object.hashAll(columns);
}

/// עמוד פיזי אחד בספר.
@immutable
class BookPage {
  /// מספר העמוד למשתמש — רץ לכל הספר, מתחיל ב-1.
  final int number;

  /// הרצועות, מלמעלה למטה.
  final List<PageBand> bands;

  /// הסעיף הראשון שמופיע בעמוד.
  final int firstSourceIndex;

  /// הסעיף האחרון שמופיע בעמוד. עולה מונוטונית בין עמודים, וזה הערך שהניווט
  /// מחפש בו בינארית: העמוד הראשון שהסעיף המבוקש מגיע אליו.
  final int lastSourceIndex;

  const BookPage({
    required this.number,
    required this.bands,
    required this.firstSourceIndex,
    required this.lastSourceIndex,
  });

  bool get isEmpty => bands.every((band) => band.isEmpty);

  Iterable<PageSlice> get slices => bands.expand((band) => band.slices);

  @override
  bool operator ==(Object other) =>
      other is BookPage &&
      other.number == number &&
      other.firstSourceIndex == firstSourceIndex &&
      other.lastSourceIndex == lastSourceIndex &&
      listEquals(other.bands, bands);

  @override
  int get hashCode =>
      Object.hash(number, firstSourceIndex, lastSourceIndex, bands.length);
}

/// ספר מעומד: רשימת עמודים והגאומטריה שבה עומדו.
@immutable
class PaginatedBook {
  final List<BookPage> pages;
  final PageGeometry geometry;

  /// מספר הסעיפים שעומדו. מבחין בין "עמוד חסר" לבין "סעיף ריק".
  final int sectionCount;

  const PaginatedBook({
    required this.pages,
    required this.geometry,
    required this.sectionCount,
  });

  int get pageCount => pages.length;

  bool get isEmpty => pages.isEmpty;

  /// אינדקס העמוד **הראשון** שבו [sourceIndex] מופיע, או 0 כשאין עמודים.
  ///
  /// החיפוש הוא על [BookPage.lastSourceIndex] ולא על הראשון: סעיף ארוך נמשך
  /// על כמה עמודים ולכולם אותו סעיף ראשון, ולכן חיפוש לפי הראשון היה מחזיר
  /// את העמוד שבו הסעיף **נגמר**. סעיף ריק שלא הגיע לשום עמוד מקבל את העמוד
  /// שמכיל את הטקסט שאחריו — זו התנהגות הניווט הרצויה.
  int pageIndexOfSource(int sourceIndex) {
    if (pages.isEmpty) return 0;
    var low = 0;
    var high = pages.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (pages[mid].lastSourceIndex < sourceIndex) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low == pages.length ? pages.length - 1 : low;
  }

  /// מספר העמוד למשתמש שבו מתחיל [sourceIndex].
  int pageNumberOfSource(int sourceIndex) =>
      pages.isEmpty ? 0 : pages[pageIndexOfSource(sourceIndex)].number;
}
