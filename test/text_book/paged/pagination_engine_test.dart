// טסטים למנוע העימוד.
//
// הגאומטריה כאן מכוילת: ברוחב טור 100 וגופן בגודל 10 עם height 1.0, שורה
// מכילה שתי מילים בנות ארבע אותיות, וטור מכיל עשר שורות בדיוק. כל המספרים
// בטסטים נגזרים מזה.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/paged/models/page_geometry.dart';
import 'package:otzaria/text_book/paged/models/paginated_book.dart';
import 'package:otzaria/text_book/paged/services/paged_text_measurer.dart';
import 'package:otzaria/text_book/paged/services/pagination_engine.dart';

/// הטורים של העמוד מכל רצועות הגוף. רצועות הכותרת אינן נכללות — הן נבדקות
/// דרך [BookPage.bands].
extension on BookPage {
  List<PageColumn> get bodyColumns => [
    for (final band in bands)
      if (band is ColumnsBand) ...band.columns,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const geometry = PageGeometry(
    width: 240,
    height: 120,
    margins: EdgeInsets.all(10),
    columns: 2,
    columnGap: 20,
    headerHeight: 0,
    sectionGap: 0,
    headingGap: 0,
  );
  const style = TextStyle(fontSize: 10, height: 1);
  const linesPerColumn = 10;

  const measurer = PagedTextMeasurer(
    width: 100,
    textScaler: TextScaler.noScaling,
    locale: Locale('he', 'IL'),
  );

  /// טקסט שתופס [lines] שורות חזותיות: שתי מילים בנות ארבע אותיות לשורה.
  String section(int lines) => List.filled(lines * 2, 'wwww').join(' ');

  /// אותו דבר ברוחב עמוד מלא (200) — ארבע מילים לשורה. לגאומטריה בת טור אחד,
  /// ולכותרת, שנמדדות על כל רוחב העמוד.
  String wideSection(int lines) => List.filled(lines * 4, 'wwww').join(' ');

  PaginationEngine engineFor(
    List<String> content, {
    Set<int> headings = const {},
    PageGeometry pageGeometry = geometry,
    PaginationRules rules = const PaginationRules(),
    InlineSpan? Function(int index)? spanOverride,
  }) {
    return PaginationEngine(
      geometry: pageGeometry,
      measurers: PagedMeasurers.forGeometry(
        geometry: pageGeometry,
        textScaler: TextScaler.noScaling,
        locale: const Locale('he', 'IL'),
        justifyText: true,
      ),
      sectionCount: content.length,
      buildSpan:
          spanOverride ??
          (index) => TextSpan(text: content[index], style: style),
      isHeading: headings.contains,
      rules: rules,
    );
  }

  PaginatedBook paginate(
    List<String> content, {
    Set<int> headings = const {},
    PageGeometry pageGeometry = geometry,
    PaginationRules rules = const PaginationRules(),
    InlineSpan? Function(int index)? spanOverride,
  }) {
    final engine = engineFor(
      content,
      headings: headings,
      pageGeometry: pageGeometry,
      rules: rules,
      spanOverride: spanOverride,
    );
    engine.run();
    return engine.snapshot();
  }

  List<PageSlice> allSlices(PaginatedBook book) =>
      book.pages.expand((page) => page.slices).toList();

  test('הכיול: עשר שורות ממלאות טור אחד בדיוק', () {
    final measured = measurer.measure(
      TextSpan(text: section(linesPerColumn), style: style),
    )!;

    expect(measured.lineCount, linesPerColumn);
    expect(measured.totalHeight, geometry.contentHeight);
  });

  group('הצבה בסיסית', () {
    test('ספר ריק — אין עמודים', () {
      expect(paginate(const []).isEmpty, isTrue);
    });

    test('סעיף קצר יחיד — עמוד אחד, טור ראשון', () {
      final book = paginate([section(1)]);

      expect(book.pageCount, 1);
      expect(book.pages.first.number, 1);
      expect(book.pages.first.bodyColumns[0].slices, hasLength(1));
      expect(book.pages.first.bodyColumns[1].isEmpty, isTrue);
    });

    test('סעיף שמילא טור — הסעיף הבא עובר לטור השני', () {
      final book = paginate([section(linesPerColumn), section(2)]);

      expect(book.pageCount, 1);
      expect(book.pages.first.bodyColumns[0].slices.single.sourceIndex, 0);
      expect(book.pages.first.bodyColumns[1].slices.single.sourceIndex, 1);
    });

    test('שני טורים מלאים — נפתח עמוד שני, והמספור רץ', () {
      final book = paginate(
        List.generate(3, (_) => section(linesPerColumn)),
      );

      expect(book.pageCount, 2);
      expect(book.pages.map((page) => page.number), [1, 2]);
      expect(book.pages[1].bodyColumns[0].slices.single.sourceIndex, 2);
    });

    test('סעיפים ריקים אינם תופסים מקום', () {
      final book = paginate([section(1), '', '', section(1)]);

      expect(book.pageCount, 1);
      expect(allSlices(book).map((slice) => slice.sourceIndex), [0, 3]);
    });

    test('גאומטריה בת טור אחד ממלאה עמוד בטור בודד', () {
      final single = geometry.singleColumn;
      final book = paginate(
        [section(linesPerColumn * 2)],
        pageGeometry: single,
      );

      expect(book.pages.first.bodyColumns, hasLength(1));
      // רוחב הטור גדל, ולכן נכנסות יותר מילים בשורה ופחות שורות בסך הכל.
      expect(book.pageCount, lessThanOrEqualTo(2));
    });
  });

  group('שבירת סעיף בין עמודים', () {
    test('הפרוסות מרצפות את כל הטקסט', () {
      final text = section(25);
      final book = paginate([text]);
      final slices = allSlices(book);

      expect(slices.length, greaterThan(2));
      expect(slices.first.charStart, 0);
      expect(slices.last.charEnd, text.length);
      for (var i = 1; i < slices.length; i++) {
        expect(
          slices[i].charStart,
          anyOf(slices[i - 1].charEnd, slices[i - 1].charEnd + 1),
          reason: 'רצף בפרוסה $i',
        );
      }
    });

    test('דגלי ההמשך מסמנים בדיוק את הקצוות', () {
      final slices = allSlices(paginate([section(25)]));

      expect(slices.first.continuesPrevious, isFalse);
      expect(slices.first.continuesNext, isTrue);
      expect(slices.last.continuesPrevious, isTrue);
      expect(slices.last.continuesNext, isFalse);
      for (final slice in slices.sublist(1, slices.length - 1)) {
        expect(slice.continuesPrevious, isTrue);
        expect(slice.continuesNext, isTrue);
      }
    });

    test('שני עמודים רצופים של אותו סעיף שומרים על מספור רץ', () {
      final book = paginate([section(45)]);

      expect(book.pageCount, greaterThan(2));
      expect(
        book.pages.map((page) => page.number),
        List.generate(book.pageCount, (i) => i + 1),
      );
    });
  });

  group('אלמנה ויתום', () {
    test('לא נדחפת שורה בודדת לטור הבא', () {
      // 11 שורות בטור של 10: בלי הכלל היו נכנסות 10 ונשארת אחת.
      final slices = allSlices(paginate([section(11)]));

      expect(slices, hasLength(2));
      expect(slices[1].continuesPrevious, isTrue);
      final firstLines = _lineCountOf(slices[0], section(11), measurer, style);
      expect(firstLines, linesPerColumn - 1);
    });

    test('פסקה אינה מתחילה בשורה בודדת בתחתית הטור', () {
      // הסעיף הראשון תופס 9 שורות, ולשני נשארת שורה אחת בלבד.
      final book = paginate([section(9), section(5)]);

      expect(book.pages.first.bodyColumns[0].slices, hasLength(1));
      expect(book.pages.first.bodyColumns[1].slices.first.sourceIndex, 1);
      expect(
        book.pages.first.bodyColumns[1].slices.first.continuesPrevious,
        isFalse,
      );
    });

    test('פסקה בת שורה אחת כן מתמלאת בשורה הפנויה האחרונה', () {
      final book = paginate([section(9), section(1)]);

      expect(book.pages.first.bodyColumns[0].slices, hasLength(2));
      expect(book.pages.first.bodyColumns[1].isEmpty, isTrue);
    });

    test('כלל שכובה מאפשר שבירה בשורה בודדת', () {
      final book = paginate(
        [section(9), section(5)],
        rules: const PaginationRules(
          minLinesToStart: 1,
          minLinesToCarry: 1,
        ),
      );

      expect(book.pages.first.bodyColumns[0].slices, hasLength(2));
      expect(
        book.pages.first.bodyColumns[0].slices.last.continuesNext,
        isTrue,
      );
    });
  });

  group('כותרות ורצועות', () {
    test('כותרת מקבלת רצועה לעצמה, בין רצועות הגוף', () {
      final book = paginate(
        [section(2), section(1), section(2)],
        headings: {1},
      );
      final bands = book.pages.first.bands;

      expect(bands, hasLength(3));
      expect(bands[0], isA<ColumnsBand>());
      expect((bands[1] as HeadingBand).slice.sourceIndex, 1);
      expect(bands[2], isA<ColumnsBand>());
    });

    test('כותרת אינה מופיעה בתוך טור', () {
      final book = paginate(
        [section(2), section(1), section(2)],
        headings: {1},
      );

      expect(
        book.pages.first.bodyColumns
            .expand((column) => column.slices)
            .map((slice) => slice.sourceIndex),
        isNot(contains(1)),
      );
    });

    test('הטורים שלפני כותרת מאוזנים, ואינם מתמלאים עד תחתית העמוד', () {
      // בלי איזון הטור הראשון היה נגמר בתחתית העמוד, השני היה נשאר ריק,
      // והכותרת לא הייתה מוצאת מקום.
      final text = section(9);
      final book = paginate([text, section(1), section(5)], headings: {1});
      final band = book.pages.first.bands.first as ColumnsBand;

      final first = _lineCountOf(
        band.columns[0].slices.single,
        text,
        measurer,
        style,
      );
      final second = _lineCountOf(
        band.columns[1].slices.single,
        text,
        measurer,
        style,
      );
      expect(first + second, 9);
      expect((first - second).abs(), lessThanOrEqualTo(1));
      expect(book.pages.first.bands, hasLength(3));
    });

    test('רצף שממלא את שני הטורים דוחה את הכותרת לעמוד הבא', () {
      final book = paginate(
        [section(19), section(1), section(5)],
        headings: {1},
      );

      expect(book.pages.first.bands, hasLength(1));
      expect(book.pages[1].bands.first, isA<HeadingBand>());
    });

    test('כותרת שאין מתחתיה מקום לשורותיה הראשונות עוברת לעמוד הבא', () {
      final book = paginate(
        [wideSection(8), section(1), wideSection(5)],
        headings: {1},
        pageGeometry: geometry.singleColumn,
      );

      expect(book.pages.first.bands, hasLength(1));
      expect(book.pages[1].bands.first, isA<HeadingBand>());
    });

    test('סעיף ריק אחרי כותרת אינו נחשב כמצטרף אליה', () {
      final book = paginate(
        [wideSection(8), section(1), '', wideSection(5)],
        headings: {1},
        pageGeometry: geometry.singleColumn,
      );

      expect(book.pages[1].bands.first, isA<HeadingBand>());
    });

    test('סעיף בלתי נמדד אחרי כותרת מזיז את הכותרת', () {
      final content = [wideSection(8), section(1), wideSection(2)];
      final book = paginate(
        content,
        headings: {1},
        pageGeometry: geometry.singleColumn,
        spanOverride: (index) => index == 2
            ? const TextSpan(
                children: [WidgetSpan(child: SizedBox(width: 5, height: 5))],
              )
            : TextSpan(text: content[index], style: style),
      );

      expect(book.pages[1].bands.first, isA<HeadingBand>());
    });

    test('כותרת בסוף הספר אינה זזה — אין מה לשמור איתה', () {
      final book = paginate(
        [wideSection(8), section(1)],
        headings: {1},
        pageGeometry: geometry.singleColumn,
      );

      expect(book.pages, hasLength(1));
      expect(book.pages.first.bands.last, isA<HeadingBand>());
    });

    test('כותרת נשארת פרוסה אחת גם כשהיא נשברת לכמה שורות', () {
      final book = paginate([wideSection(3)], headings: {0});
      final band = book.pages.first.bands.single as HeadingBand;

      expect(band.slice.charStart, 0);
      expect(band.slice.charEnd, wideSection(3).length);
      expect(band.slice.continuesNext, isFalse);
    });
  });

  group('מרווחי הרצועות', () {
    const spaced = PageGeometry(
      width: 240,
      height: 120,
      margins: EdgeInsets.all(10),
      columns: 2,
      columnGap: 20,
      headerHeight: 0,
      sectionGap: 3,
      headingGap: 12,
    );
    const heading = HeadingBand(
      PageSlice(sourceIndex: 0, charStart: 0, charEnd: 1),
    );
    const body = ColumnsBand([]);

    test('רצועה ראשונה בעמוד אינה מקבלת מרווח', () {
      expect(PageBand.gapBefore(heading, null, spaced), 0);
      expect(PageBand.gapBefore(body, null, spaced), 0);
    });

    test('אין מרווח בין כותרת לגוף שמתחתיה', () {
      expect(PageBand.gapBefore(body, heading, spaced), 0);
    });

    test('כותרת אחרי גוף מקבלת את מרווח הכותרת', () {
      expect(PageBand.gapBefore(heading, body, spaced), spaced.headingGap);
    });

    test('שתי כותרות רצופות מקבלות את המרווח הקטן', () {
      expect(PageBand.gapBefore(heading, heading, spaced), spaced.sectionGap);
    });
  });

  group('מקרי קצה שעלולים לתקוע את העימוד', () {
    test('שורה גבוהה מטור שלם מוצבת בכל זאת', () {
      final book = paginate(
        ['w'],
        spanOverride: (_) => const TextSpan(
          text: 'w',
          style: TextStyle(fontSize: 300, height: 1),
        ),
      );

      expect(book.pageCount, 1);
      expect(book.pages.first.bodyColumns[0].slices, hasLength(1));
      expect(book.pages.first.bodyColumns[1].isEmpty, isTrue);
    });

    test('כמה שורות גבוהות מטור מקבלות טור לכל אחת, בלי להיתקע', () {
      // מילה ארוכה מהטור נשברת לאותיות, וכל אות גבוהה מטור שלם.
      final book = paginate(
        ['wwww'],
        spanOverride: (_) => const TextSpan(
          text: 'wwww',
          style: TextStyle(fontSize: 300, height: 1),
        ),
      );
      final columns = book.pages.expand((page) => page.bodyColumns).toList();

      expect(allSlices(book), hasLength(4));
      for (final column in columns.where((c) => !c.isEmpty)) {
        expect(column.slices, hasLength(1));
      }
    });

    test('סעיף גבוה מכמה טורים נשבר ואינו נתקע', () {
      final book = paginate([section(200)]);

      expect(book.pageCount, greaterThan(5));
      expect(allSlices(book).last.charEnd, section(200).length);
    });

    test('סעיף שאינו נמדד מקבל טור לעצמו', () {
      final book = paginate(
        [section(2), 'x', section(2)],
        spanOverride: (index) => index == 1
            ? const TextSpan(
                children: [
                  TextSpan(text: 'x'),
                  WidgetSpan(child: SizedBox(width: 5, height: 5)),
                ],
              )
            : TextSpan(text: section(2), style: style),
      );

      final columns = book.pages.expand((page) => page.bodyColumns).toList();
      final unmeasurable = columns.firstWhere(
        (column) => column.slices.any((slice) => slice.sourceIndex == 1),
      );

      expect(unmeasurable.slices, hasLength(1));
    });
  });

  group('ניווט לעמוד', () {
    test('סעיף שנמצא באמצע עמוד מוחזר לעמוד שלו', () {
      final book = paginate(List.generate(6, (_) => section(5)));

      // 4 סעיפים בעמוד הראשון (2 בכל טור), השאר בשני.
      expect(book.pageIndexOfSource(0), 0);
      expect(book.pageIndexOfSource(3), 0);
      expect(book.pageIndexOfSource(4), 1);
    });

    test('סעיף שנמשך על כמה עמודים מוחזר לעמוד שבו הוא מתחיל', () {
      final book = paginate([section(5), section(60), section(5)]);
      final long = book.pageIndexOfSource(1);

      expect(long, 0);
      expect(
        book.pages[long].slices.any((slice) => slice.sourceIndex == 1),
        isTrue,
      );
      expect(book.pageIndexOfSource(2), book.pageCount - 1);
    });

    test('אינדקס מעל הסעיף האחרון נחתך לעמוד האחרון', () {
      final book = paginate([section(2), section(2)]);

      expect(book.pageIndexOfSource(999), book.pageCount - 1);
    });

    test('מספר העמוד למשתמש מתחיל ב-1', () {
      final book = paginate(List.generate(6, (_) => section(5)));

      expect(book.pageNumberOfSource(0), 1);
      expect(book.pageNumberOfSource(4), 2);
    });

    test('ספר בלי עמודים מחזיר אפס', () {
      expect(paginate(const []).pageNumberOfSource(0), 0);
    });
  });

  group('עצירה והמשך', () {
    test('עימוד מדורג מגיע לאותה תוצאה כמו עימוד בבת אחת', () {
      final content = [
        section(3),
        section(14),
        section(1),
        section(7),
        section(22),
        section(2),
      ];

      final full = paginate(content, headings: {2});

      final stepped = engineFor(content, headings: {2});
      while (!stepped.isDone) {
        var ran = false;
        stepped.run(
          shouldStop: () {
            ran = true;
            return true;
          },
        );
        expect(ran, isTrue);
      }

      expect(stepped.snapshot().pages, full.pages);
    });

    test('התקדמות עולה מאפס לאחד', () {
      // ההתקדמות נמדדת ברצועות: רצועה אחת מכניסה כמה סעיפים יחד, ולכן הספר
      // כאן ארוך מעמוד.
      final engine = engineFor(List.generate(8, (_) => section(5)));

      expect(engine.progress, 0);
      engine.run(shouldStop: () => engine.sectionsDone >= 4);
      expect(engine.progress, 0.5);
      engine.run();
      expect(engine.progress, 1);
      expect(engine.isDone, isTrue);
    });

    test('snapshot באמצע הדרך מחזיר את העמוד שבבנייה ואינו פוגע בהמשך', () {
      final engine = engineFor(List.generate(8, (_) => section(5)));

      engine.run(shouldStop: () => engine.sectionsDone >= 3);
      final partial = engine.snapshot();
      expect(partial.pageCount, 1);

      engine.run();
      final complete = engine.snapshot();
      expect(complete.pageCount, 2);
      // אותם סעיפים בעמוד הראשון גם אחרי ההמשך.
      expect(
        complete.pages.first.slices.take(3).map((s) => s.sourceIndex),
        [0, 1, 2],
      );
    });
  });
}

/// מספר השורות שפרוסה תופסת, לצורך בדיקת כלל האלמנה.
int _lineCountOf(
  PageSlice slice,
  String text,
  PagedTextMeasurer measurer,
  TextStyle style,
) {
  final sliced = TextSpan(
    text: text.substring(slice.charStart, slice.charEnd),
    style: style,
  );
  return measurer.measure(sliced)!.lineCount;
}
