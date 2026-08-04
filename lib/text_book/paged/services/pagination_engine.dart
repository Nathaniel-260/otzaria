import 'dart:math' as math;

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

  /// כמה שורות מהסעיף שאחרי הכותרת חייבות להיכנס מתחתיה באותו עמוד.
  final int minLinesAfterHeading;

  const PaginationRules({
    this.minLinesToStart = 2,
    this.minLinesToCarry = 2,
    this.minLinesAfterHeading = 2,
  });
}

/// תקרת ההצצה קדימה. הרצף חסום בגובה, אבל סעיף ריק אינו תופס גובה ורצף שכולו
/// ריק היה נסקר עד סוף הספר.
const int _maxLookaheadSections = 512;

/// עימוד ספר לעמודים פיזיים, בצורה שניתן לעצור ולהמשיך.
///
/// העמוד בנוי **רצועות** זו מעל זו: כותרת פורשת על כל רוחבו, ורצועת הגוף
/// שאחריה מתחלקת לטורים מחדש. רצועת גוף שאחריה כותרת מאוזנת — שני הטורים
/// מקבלים גובה שווה, אחרת הראשון היה מתמלא עד למטה והכותרת הייתה יורדת
/// מהעמוד.
///
/// מדידת טקסט אפשרית רק ב-isolate הראשי (flutter#30604), ולכן העימוד רץ על
/// ה-UI thread ונחתך לפרוסות זמן: [run] מקבל תנאי עצירה, ו-[snapshot] מחזיר
/// את מה שהצטבר עד כה בלי לפגוע בהמשך.
class PaginationEngine {
  final PageGeometry geometry;

  /// מודד הגוף ומודד הכותרת. הבחירה ביניהם נגזרת מ-[isHeading] בלבד, ולכן כל
  /// סעיף נמדד תמיד באותו רוחב שבו יצויר.
  final PagedMeasurers measurers;

  /// מספר הסעיפים ב-`content` של הספר.
  final int sectionCount;

  /// בונה את הספאן של סעיף. null = אין מה להציג.
  final InlineSpan? Function(int index) buildSpan;

  final bool Function(int index) isHeading;
  final PaginationRules rules;

  PaginationEngine({
    required this.geometry,
    required this.measurers,
    required this.sectionCount,
    required this.buildSpan,
    required this.isHeading,
    this.rules = const PaginationRules(),
  });

  final List<BookPage> _pages = [];

  /// הרצועות של העמוד שבבנייה.
  final List<PageBand> _bands = [];

  /// הגובה שהרצועות תפסו בעמוד, כולל המרווחים ביניהן.
  double _pageUsed = 0;

  int _nextSection = 0;

  /// השורה שממתינה בסעיף [_nextSection], כשסעיף נחתך בין עמודים.
  int _pendingLine = 0;

  int? _pageFirst;
  int? _pageLast;

  /// מדידות שההצצה קדימה ביצעה ועוד לא הוצבו. נגזם אחרי כל רצועה, ולכן הוא
  /// חלון קטן ולא מטמון של הספר.
  final Map<int, _MeasuredSection> _measured = {};

  int get sectionsDone => _nextSection;

  bool get isDone => _nextSection >= sectionCount;

  double get progress => sectionCount == 0 ? 1 : _nextSection / sectionCount;

  double get _roomLeft => geometry.contentHeight - _pageUsed;

  /// מעמד רצועות עד ש-[shouldStop] מחזיר true, או עד סוף הספר.
  /// [shouldStop] נבדק אחרי כל רצועה, ולכן רצועה בודדת תמיד נגמרת במלואה.
  void run({bool Function()? shouldStop}) {
    while (_nextSection < sectionCount) {
      if (isHeading(_nextSection)) {
        _placeHeadingBand(_nextSection);
      } else {
        _placeBodyBand();
      }
      _measured.removeWhere((index, _) => index < _nextSection);
      if (shouldStop != null && shouldStop()) return;
    }
  }

  /// העמודים שהצטברו, כולל העמוד שבבנייה. אינו משנה את מצב המנוע, ולכן ניתן
  /// לקרוא לו בכל שלב כדי להציג עימוד חלקי.
  PaginatedBook snapshot() {
    final pages = List<BookPage>.of(_pages);
    if (_bands.isNotEmpty) pages.add(_buildPage());
    return PaginatedBook(
      pages: List.unmodifiable(pages),
      geometry: geometry,
      sectionCount: sectionCount,
    );
  }

  void _placeHeadingBand(int index) {
    final section = _sectionAt(index);
    final paragraph = section.paragraph;
    if (section.span == null || (paragraph?.isEmpty ?? false)) {
      _advanceTo(index + 1);
      return;
    }
    if (paragraph == null) {
      _placeUnmeasurableBand(index);
      return;
    }

    final band = HeadingBand(
      PageSlice(sourceIndex: index, charStart: 0, charEnd: section.textLength),
    );
    final needed =
        PageBand.gapBefore(band, _bands.lastOrNull, geometry) +
        paragraph.totalHeight;
    if (_bands.isNotEmpty &&
        (_roomLeft < needed ||
            _headingWouldBeOrphan(index, _roomLeft - needed))) {
      _newPage();
    }

    _pageUsed +=
        PageBand.gapBefore(band, _bands.lastOrNull, geometry) +
        paragraph.totalHeight;
    _addBand(band);
    _advanceTo(index + 1);
  }

  void _placeBodyBand() {
    var run = _collectRun();
    if (run.sections.isEmpty) {
      // או סעיפים חסרי תוכן שאין מה לעשות בהם, או סעיף בלתי נמדד שקטע את הסקירה.
      if (run.scannedTo > _nextSection) {
        _advanceTo(run.scannedTo);
      } else {
        _placeUnmeasurableBand(_nextSection);
      }
      return;
    }

    // רצועה שאין בה מקום גם לשורה אחת הייתה חורגת מהעמוד בציור.
    if (_bands.isNotEmpty && _roomLeft < _firstLineHeight(run)) {
      _newPage();
      run = _collectRun();
    }

    final start = _RunCursor(
      0,
      run.sections.first.index == _nextSection ? _pendingLine : 0,
    );
    final columns = List.generate(geometry.columns, (_) => <PageSlice>[]);
    final result = _layoutRun(
      run,
      start,
      _bandHeightFor(run, start),
      geometry.columns,
      columns,
    );

    _pageUsed += result.height;
    _addBand(
      ColumnsBand(
        List.unmodifiable([
          for (final slices in columns) PageColumn(List.unmodifiable(slices)),
        ]),
      ),
    );

    final placedAll = result.end.section >= run.sections.length;
    if (placedAll) {
      _advanceTo(run.scannedTo);
    } else {
      _nextSection = run.sections[result.end.section].index;
      _pendingLine = result.end.line;
    }
    // רצף שלא נגמר — הרצועה מילאה את כל הטורים, והעמוד תפוס.
    if (!placedAll || !run.complete) _newPage();
  }

  /// סעיף שלא ניתן למדוד (למשל ספאן עם placeholder) מקבל עמוד לעצמו.
  void _placeUnmeasurableBand(int index) {
    final section = _sectionAt(index);
    _newPage();
    _addBand(
      ColumnsBand(
        List.unmodifiable([
          PageColumn(
            List.unmodifiable([
              PageSlice(
                sourceIndex: index,
                charStart: 0,
                charEnd: section.textLength,
              ),
            ]),
          ),
          for (var i = 1; i < geometry.columns; i++) PageColumn.empty,
        ]),
      ),
    );
    _pageUsed = geometry.contentHeight;
    _advanceTo(index + 1);
  }

  void _addBand(PageBand band) {
    _bands.add(band);
    for (final slice in band.slices) {
      _pageFirst ??= slice.sourceIndex;
      _pageLast = slice.sourceIndex;
    }
  }

  void _advanceTo(int index) {
    _nextSection = index;
    _pendingLine = 0;
  }

  void _newPage() {
    if (_bands.isEmpty) return;
    _pages.add(_buildPage());
    _bands.clear();
    _pageUsed = 0;
    _pageFirst = null;
    _pageLast = null;
  }

  BookPage _buildPage() {
    // עמוד שכל תוכנו המשך של סעיף מהעמוד הקודם מקבל את אותו סעיף בשני הקצוות.
    final first = _pageFirst ?? _pages.lastOrNull?.lastSourceIndex ?? 0;
    return BookPage(
      number: _pages.length + 1,
      bands: List.unmodifiable(_bands),
      firstSourceIndex: first,
      lastSourceIndex: _pageLast ?? first,
    );
  }

  /// הסעיפים מ-[_nextSection] ועד הכותרת הבאה, עם המדידות שלהם.
  ///
  /// הסקירה נעצרת ברגע שגובה הרצף עובר את מה שהעמוד יכול להכיל — אז אין מה
  /// לאזן, ומדידת שאר הרצף הייתה עבודה לחינם וזיכרון מבוזבז.
  _Run _collectRun() {
    final budget = math.max(_roomLeft, 0) * geometry.columns;
    final sections = <_MeasuredSection>[];
    var total = 0.0;
    var index = _nextSection;
    var complete = true;

    while (index < sectionCount && !isHeading(index)) {
      if (sections.length >= _maxLookaheadSections) {
        complete = false;
        break;
      }
      final section = _sectionAt(index);
      if (section.span == null) {
        index++;
        continue;
      }
      final paragraph = section.paragraph;
      // סעיף בלתי נמדד תופס עמוד לעצמו — הרצף נגמר לפניו.
      if (paragraph == null) break;
      if (paragraph.isEmpty) {
        index++;
        continue;
      }

      if (sections.isNotEmpty) total += geometry.sectionGap;
      total += paragraph.totalHeight;
      sections.add(section);
      index++;
      if (total > budget) {
        complete = false;
        break;
      }
    }

    return _Run(sections: sections, scannedTo: index, complete: complete);
  }

  double _firstLineHeight(_Run run) {
    final first = run.sections.first;
    final paragraph = first.paragraph!;
    final line = first.index == _nextSection ? _pendingLine : 0;
    if (line >= paragraph.lineCount) return 0;
    return paragraph.heightOfFirst(line + 1) - paragraph.heightOfFirst(line);
  }

  /// גובה הטורים ברצועה.
  ///
  /// ברירת המחדל היא כל המקום שנשאר — טור מתמלא עד למטה, כמו בכל טיפוגרפיה
  /// דו-טורית. האיזון נכנס רק כשכותרת ממתינה אחרי הרצף: בלעדיו הטור הראשון
  /// היה נגמר בתחתית העמוד, השני היה נשאר ריק, והכותרת לא הייתה מוצאת מקום.
  double _bandHeightFor(_Run run, _RunCursor start) {
    final room = _roomLeft;
    if (geometry.columns == 1 || !run.complete) return room;
    if (run.scannedTo >= sectionCount || !isHeading(run.scannedTo)) return room;

    final headingRoom = _roomForHeading(run.scannedTo);
    if (headingRoom == null) return room;

    return _minimalBandHeight(run, start, room - headingRoom) ?? room;
  }

  /// הגובה שהכותרת שב-[index] דורשת מתחת לרצועה: המרווח שמעליה, גובהה,
  /// והשורות הראשונות של ההמשך שחייבות להישאר איתה.
  double? _roomForHeading(int index) {
    final heading = _sectionAt(index).paragraph;
    if (heading == null || heading.isEmpty) return null;

    final follow = _followingBody(index);
    final lines = follow == null
        ? 0
        : math.min(follow.lineCount, rules.minLinesAfterHeading);
    return geometry.headingGap +
        heading.totalHeight +
        (follow?.heightOfFirst(lines) ?? 0);
  }

  /// הפסקה של הסעיף שיצטרף לכותרת שב-[index]. סעיף ריק אינו מצטרף, ולכן
  /// מדלגים עליו.
  MeasuredParagraph? _followingBody(int index) {
    for (var next = index + 1; next < sectionCount; next++) {
      final section = _sectionAt(next);
      if (section.span == null) continue;
      final paragraph = section.paragraph;
      if (paragraph == null) return null;
      if (paragraph.isEmpty) continue;
      return paragraph;
    }
    return null;
  }

  /// הגובה הקטן ביותר שבו כל הרצף מ-[start] נכנס בטורי הרצועה, או null כשגם
  /// [ceiling] אינו מספיק.
  ///
  /// החיפוש הוא על גבהים שהם קצה שורה בפועל; כל גובה שביניהם נותן בדיוק אותה
  /// שבירה כמו המועמד שמתחתיו. ההצבה עצמה היא זו שמדמה, ולכן כללי האלמנה
  /// והיתום נכנסים לחשבון ולא רק סכום הגבהים.
  double? _minimalBandHeight(_Run run, _RunCursor start, double ceiling) {
    if (ceiling <= 0) return null;
    final candidates = _candidateHeights(run, start, ceiling);

    var low = 0;
    var high = candidates.length - 1;
    double? best;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (_runFits(run, start, candidates[mid])) {
        best = candidates[mid];
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }
    return best;
  }

  /// הגבהים שבהם טור נגמר בסוף שורה, עולים, עד [ceiling].
  List<double> _candidateHeights(_Run run, _RunCursor start, double ceiling) {
    final heights = <double>[];
    var total = 0.0;
    for (var s = start.section; s < run.sections.length; s++) {
      final paragraph = run.sections[s].paragraph!;
      final from = s == start.section ? start.line : 0;
      if (s > start.section) total += geometry.sectionGap;
      final base = paragraph.heightOfFirst(from);
      for (var line = from + 1; line <= paragraph.lineCount; line++) {
        final height = total + paragraph.heightOfFirst(line) - base;
        if (height > ceiling) return heights;
        heights.add(height);
      }
      total += paragraph.totalHeight - base;
    }
    return heights;
  }

  bool _runFits(_Run run, _RunCursor start, double height) =>
      _layoutRun(run, start, height, geometry.columns, null).end.section >=
      run.sections.length;

  /// ממלא [columnCount] טורים בגובה [height] מ-[start]. כותב את הפרוסות ל-[into]
  /// כשהוא ניתן, ומחזיר את המקום שבו נעצר.
  ///
  /// **אותה פונקציה מדמה וגם מציבה.** חישוב נפרד לאיזון היה יכול לתת תשובה
  /// אחרת מזו שתקרה, והכותרת הייתה נופלת מהעמוד.
  _LayoutResult _layoutRun(
    _Run run,
    _RunCursor start,
    double height,
    int columnCount,
    List<List<PageSlice>>? into,
  ) {
    var section = start.section;
    var line = start.line;
    var column = 0;
    var used = 0.0;
    var columnEmpty = true;
    var tallest = 0.0;

    bool nextColumn() {
      if (column + 1 >= columnCount) return false;
      column++;
      used = 0;
      columnEmpty = true;
      return true;
    }

    while (section < run.sections.length) {
      final paragraph = run.sections[section].paragraph!;
      var fit = paragraph.linesFittingFrom(line, height - used);

      if (fit == 0) {
        if (!columnEmpty) {
          if (!nextColumn()) break;
          continue;
        }
        // שורה גבוהה מהרצועה. מוצבת בכל זאת — אחרת אין התקדמות.
        fit = 1;
      }

      if (!columnEmpty && _bodyWouldStartTooThin(paragraph, line, fit)) {
        if (!nextColumn()) break;
        continue;
      }

      fit = _withoutWidow(paragraph, line, fit);

      into?[column].add(
        PageSlice(
          sourceIndex: run.sections[section].index,
          charStart: paragraph.lineStarts[line],
          charEnd: paragraph.lineEnds[line + fit - 1],
          continuesPrevious: line > 0,
          continuesNext: line + fit < paragraph.lineCount,
        ),
      );
      used +=
          paragraph.heightOfFirst(line + fit) - paragraph.heightOfFirst(line);
      if (used > tallest) tallest = used;
      columnEmpty = false;
      line += fit;

      if (line < paragraph.lineCount) {
        if (!nextColumn()) break;
        continue;
      }
      section++;
      line = 0;
      // המרווח נספר גם אחרי הסעיף האחרון: סעיף שנגמר בדיוק בתחתית הטור אינו
      // מוריש את המרווח לסעיף הבא, וזה מה שהציור מצייר.
      used += geometry.sectionGap;
    }

    return _LayoutResult(_RunCursor(section, line), tallest);
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
    final follow = _followingBody(index);
    // סעיף בלתי נמדד פותח עמוד לעצמו, כלומר הכותרת תישאר לבדה.
    if (follow == null) return _hasUnmeasurableAfter(index);
    final needed = math.min(follow.lineCount, rules.minLinesAfterHeading);
    return _linesPlacedFor(follow, roomAfter) < needed;
  }

  bool _hasUnmeasurableAfter(int index) {
    for (var next = index + 1; next < sectionCount; next++) {
      final section = _sectionAt(next);
      if (section.span == null) continue;
      if (section.paragraph == null) return true;
      if (section.paragraph!.isEmpty) continue;
      return false;
    }
    // אין סעיף שיצטרף לכותרת — אין מה לשמור איתה.
    return false;
  }

  /// כמה שורות מהסעיף יוצבו **בפועל** בטור הראשון של רצועה בגובה [room].
  int _linesPlacedFor(MeasuredParagraph paragraph, double room) {
    final fit = paragraph.linesFittingFrom(0, room);
    if (fit == 0) return 0;
    return _withoutWidow(paragraph, 0, fit);
  }

  _MeasuredSection _sectionAt(int index) {
    final cached = _measured[index];
    if (cached != null) return cached;

    final span = buildSpan(index);
    // הכותרת נמדדת על כל רוחב העמוד כי כך היא מצוירת; סעיף גוף — ברוחב טור.
    final measurer = isHeading(index) ? measurers.heading : measurers.body;
    final result = _MeasuredSection(
      index: index,
      span: span,
      paragraph: span == null ? null : measurer.measure(span),
      textLength: span == null
          ? 0
          : span.toPlainText(includeSemanticsLabels: false).length,
    );
    _measured[index] = result;
    return result;
  }
}

/// מקום בתוך רצף: הסעיף (אינדקס ברשימת הרצף) והשורה בתוכו.
@immutable
class _RunCursor {
  final int section;
  final int line;

  const _RunCursor(this.section, this.line);
}

class _LayoutResult {
  final _RunCursor end;

  /// גובה הרצועה בפועל — הטור הגבוה שבה.
  final double height;

  const _LayoutResult(this.end, this.height);
}

/// רצף סעיפי גוף רצופים, עד הכותרת הבאה.
class _Run {
  /// רק סעיפים שיש בהם תוכן והם נמדדו.
  final List<_MeasuredSection> sections;

  /// הסעיף הראשון שאינו ברצף: הכותרת הבאה, סעיף בלתי נמדד, או סוף הספר.
  final int scannedTo;

  /// כל הרצף נסקר. false כשהסקירה נעצרה בתקציב — אז אין מה לאזן.
  final bool complete;

  const _Run({
    required this.sections,
    required this.scannedTo,
    required this.complete,
  });
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
