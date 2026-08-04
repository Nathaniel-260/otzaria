import 'package:flutter/material.dart';
import 'package:otzaria/text_book/paged/models/page_geometry.dart';
import 'package:otzaria/text_book/paged/models/paginated_book.dart';
import 'package:otzaria/text_book/paged/services/paged_text_measurer.dart';

/// חוקי שבירה טיפוגרפיים. כולם נכנעים לאילוץ אחד: טור ריק חייב לקבל תוכן,
/// אחרת העימוד נתקע.
@immutable
class PaginationRules {
  /// כמה שורות של פסקה חייבות להיכנס כדי להתחיל אותה בטור הזה. פחות מזה —
  /// כל הפסקה עוברת לטור הבא, ולא נשארת שורה בודדת בתחתית.
  final int minLinesToStart;

  /// כמה שורות חייבות לעבור לטור הבא. שורה בודדת בראש טור נראית כשגיאה.
  final int minLinesToCarry;

  /// כמה שורות מהסעיף שאחרי הכותרת חייבות להיכנס מתחתיה באותו טור.
  final int minLinesAfterHeading;

  const PaginationRules({
    this.minLinesToStart = 2,
    this.minLinesToCarry = 2,
    this.minLinesAfterHeading = 2,
  });
}

/// עימוד ספר לעמודים פיזיים, בצורה שניתן לעצור ולהמשיך.
///
/// מדידת טקסט אפשרית רק ב-isolate הראשי (flutter#30604), ולכן העימוד רץ על
/// ה-UI thread ונחתך לפרוסות זמן: [run] מקבל תנאי עצירה, ו-[snapshot] מחזיר
/// את מה שהצטבר עד כה בלי לפגוע בהמשך.
class PaginationEngine {
  final PageGeometry geometry;
  final PagedTextMeasurer measurer;

  /// מספר הסעיפים ב-`content` של הספר.
  final int sectionCount;

  /// בונה את הספאן של סעיף. null = אין מה להציג.
  final InlineSpan? Function(int index) buildSpan;

  final bool Function(int index) isHeading;
  final PaginationRules rules;

  PaginationEngine({
    required this.geometry,
    required this.measurer,
    required this.sectionCount,
    required this.buildSpan,
    required this.isHeading,
    this.rules = const PaginationRules(),
  });

  final List<BookPage> _pages = [];
  List<List<PageSlice>> _columns = [];
  int _columnIndex = 0;

  /// הגובה שנתפס בטור הנוכחי.
  double _used = 0;
  int _nextSection = 0;
  int? _pageFirst;
  int? _pageLast;

  /// מדידה אחרונה. מספיקה כי הסעיפים מעובדים בסדר, והצצה קדימה לכותרת
  /// מבקשת בדיוק את הסעיף שיטופל בסבב הבא.
  _MeasuredSection? _cache;

  int get sectionsDone => _nextSection;

  bool get isDone => _nextSection >= sectionCount;

  double get progress => sectionCount == 0 ? 1 : _nextSection / sectionCount;

  /// מעמד סעיפים עד ש-[shouldStop] מחזיר true, או עד סוף הספר.
  /// [shouldStop] נבדק אחרי כל סעיף, ולכן סעיף בודד תמיד נגמר במלואו.
  void run({bool Function()? shouldStop}) {
    if (_columns.isEmpty) _columns = _freshColumns();
    while (_nextSection < sectionCount) {
      _place(_nextSection);
      _nextSection++;
      if (shouldStop != null && shouldStop()) return;
    }
  }

  /// העמודים שהצטברו, כולל העמוד שבבנייה. אינו משנה את מצב המנוע, ולכן ניתן
  /// לקרוא לו בכל שלב כדי להציג עימוד חלקי.
  PaginatedBook snapshot() {
    final pages = List<BookPage>.of(_pages);
    if (_columns.any((column) => column.isNotEmpty)) pages.add(_buildPage());
    return PaginatedBook(
      pages: List.unmodifiable(pages),
      geometry: geometry,
      sectionCount: sectionCount,
    );
  }

  List<List<PageSlice>> _freshColumns() =>
      List.generate(geometry.columns, (_) => <PageSlice>[]);

  List<PageSlice> get _current => _columns[_columnIndex];

  void _place(int index) {
    final section = _sectionAt(index);
    if (section.span == null) return;

    final paragraph = section.paragraph;
    if (paragraph == null) {
      _placeUnmeasurable(index, section.textLength);
      return;
    }
    if (paragraph.isEmpty) return;

    final heading = isHeading(index);
    var line = 0;

    while (line < paragraph.lineCount) {
      final columnEmpty = _current.isEmpty;
      final available = geometry.contentHeight - _used;
      var fit = paragraph.linesFittingFrom(line, available);

      if (fit == 0) {
        if (!columnEmpty) {
          _nextColumn();
          continue;
        }
        // שורה גבוהה מטור שלם. מוצבת בכל זאת — אחרת אין התקדמות.
        fit = 1;
      }

      if (!columnEmpty && _shouldDefer(index, paragraph, line, fit, heading)) {
        _nextColumn();
        continue;
      }

      fit = _withoutWidow(paragraph, line, fit);

      _current.add(
        PageSlice(
          sourceIndex: index,
          charStart: paragraph.lineStarts[line],
          charEnd: paragraph.lineEnds[line + fit - 1],
          continuesPrevious: line > 0,
          continuesNext: line + fit < paragraph.lineCount,
        ),
      );
      _pageFirst ??= index;
      _pageLast = index;
      _used +=
          paragraph.heightOfFirst(line + fit) - paragraph.heightOfFirst(line);
      line += fit;

      if (line < paragraph.lineCount) _nextColumn();
    }

    _used += geometry.sectionGap;
  }

  /// האם להזיז את מה שנותר לטור הבא במקום להציב אותו כאן.
  bool _shouldDefer(
    int index,
    MeasuredParagraph paragraph,
    int line,
    int fit,
    bool heading,
  ) {
    final remaining = paragraph.lineCount - line - fit;

    if (heading) {
      if (remaining > 0) return true;
      final roomAfter =
          geometry.contentHeight -
          _used -
          paragraph.heightFrom(line) -
          geometry.sectionGap;
      return _headingWouldBeOrphan(index, roomAfter);
    }

    return _bodyWouldStartTooThin(paragraph, line, fit);
  }

  bool _bodyWouldStartTooThin(
    MeasuredParagraph paragraph,
    int line,
    int fit,
  ) =>
      line == 0 &&
      fit < rules.minLinesToStart &&
      paragraph.lineCount >= rules.minLinesToStart;

  /// מקצר את הפרוסה כדי שלא תישאר שורה בודדת לטור הבא.
  int _withoutWidow(MeasuredParagraph paragraph, int line, int fit) {
    final remaining = paragraph.lineCount - line - fit;
    if (remaining <= 0 || remaining >= rules.minLinesToCarry) return fit;
    final give = rules.minLinesToCarry - remaining;
    return fit - give >= 1 ? fit - give : fit;
  }

  bool _headingWouldBeOrphan(int index, double roomAfter) {
    // סעיף ריק אינו מצטרף לכותרת, ולכן מדלגים עליו אל הסעיף שכן יצטרף.
    var next = index + 1;
    while (next < sectionCount) {
      final section = _sectionAt(next);
      if (section.span == null) {
        next++;
        continue;
      }
      final paragraph = section.paragraph;
      // סעיף בלתי נמדד פותח טור לעצמו, כלומר הכותרת תישאר לבדה.
      if (paragraph == null) return true;
      if (paragraph.isEmpty) {
        next++;
        continue;
      }
      final needed = paragraph.lineCount < rules.minLinesAfterHeading
          ? paragraph.lineCount
          : rules.minLinesAfterHeading;
      return _linesPlacedFor(paragraph, roomAfter) < needed;
    }
    // אין סעיף שיצטרף לכותרת — אין מה לשמור איתה.
    return false;
  }

  /// כמה שורות מהסעיף יוצבו **בפועל** בטור שנשארו בו [room] פיקסלים.
  ///
  /// חייבת לעבור דרך אותה שרשרת שמשמשת בהצבה עצמה. חישוב נפרד היה נותן תשובה
  /// אחרת מזו שתקרה, והכותרת הייתה נשארת יתומה בתחתית הטור.
  int _linesPlacedFor(MeasuredParagraph paragraph, double room) {
    final fit = paragraph.linesFittingFrom(0, room);
    if (fit == 0) return 0;
    if (_bodyWouldStartTooThin(paragraph, 0, fit)) return 0;
    return _withoutWidow(paragraph, 0, fit);
  }

  /// סעיף שלא ניתן למדוד (למשל ספאן עם placeholder) מקבל טור לעצמו.
  void _placeUnmeasurable(int index, int textLength) {
    if (_current.isNotEmpty) _nextColumn();
    _current.add(
      PageSlice(sourceIndex: index, charStart: 0, charEnd: textLength),
    );
    _pageFirst ??= index;
    _pageLast = index;
    _used = geometry.contentHeight;
  }

  void _nextColumn() {
    _used = 0;
    _columnIndex++;
    if (_columnIndex < geometry.columns) return;
    _pages.add(_buildPage());
    _columns = _freshColumns();
    _columnIndex = 0;
    _pageFirst = null;
    _pageLast = null;
  }

  BookPage _buildPage() {
    // עמוד שכל תוכנו המשך של סעיף מהעמוד הקודם מקבל את אותו סעיף בשני הקצוות.
    final first = _pageFirst ?? _pages.lastOrNull?.lastSourceIndex ?? 0;
    return BookPage(
      number: _pages.length + 1,
      columns: _columns
          .map((slices) => PageColumn(List.unmodifiable(slices)))
          .toList(growable: false),
      firstSourceIndex: first,
      lastSourceIndex: _pageLast ?? first,
    );
  }

  _MeasuredSection _sectionAt(int index) {
    final cached = _cache;
    if (cached != null && cached.index == index) return cached;

    final span = buildSpan(index);
    final result = _MeasuredSection(
      index: index,
      span: span,
      paragraph: span == null ? null : measurer.measure(span),
      textLength: span == null
          ? 0
          : span.toPlainText(includeSemanticsLabels: false).length,
    );
    _cache = result;
    return result;
  }
}

class _MeasuredSection {
  final int index;
  final InlineSpan? span;
  final MeasuredParagraph? paragraph;
  final int textLength;

  const _MeasuredSection({
    required this.index,
    required this.span,
    required this.paragraph,
    required this.textLength,
  });
}
