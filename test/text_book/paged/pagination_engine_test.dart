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

  PaginationEngine engineFor(
    List<String> content, {
    Set<int> headings = const {},
    PageGeometry pageGeometry = geometry,
    PaginationRules rules = const PaginationRules(),
    InlineSpan? Function(int index)? spanOverride,
  }) {
    return PaginationEngine(
      geometry: pageGeometry,
      measurer: PagedTextMeasurer(
        width: pageGeometry.columnWidth,
        textScaler: TextScaler.noScaling,
        locale: const Locale('he', 'IL'),
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
      expect(book.pages.first.columns[0].slices, hasLength(1));
      expect(book.pages.first.columns[1].isEmpty, isTrue);
    });

    test('סעיף שמילא טור — הסעיף הבא עובר לטור השני', () {
      final book = paginate([section(linesPerColumn), section(2)]);

      expect(book.pageCount, 1);
      expect(book.pages.first.columns[0].slices.single.sourceIndex, 0);
      expect(book.pages.first.columns[1].slices.single.sourceIndex, 1);
    });

    test('שני טורים מלאים — נפתח עמוד שני, והמספור רץ', () {
      final book = paginate(
        List.generate(3, (_) => section(linesPerColumn)),
      );

      expect(book.pageCount, 2);
      expect(book.pages.map((page) => page.number), [1, 2]);
      expect(book.pages[1].columns[0].slices.single.sourceIndex, 2);
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

      expect(book.pages.first.columns, hasLength(1));
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

      expect(book.pages.first.columns[0].slices, hasLength(1));
      expect(book.pages.first.columns[1].slices.first.sourceIndex, 1);
      expect(
        book.pages.first.columns[1].slices.first.continuesPrevious,
        isFalse,
      );
    });

    test('פסקה בת שורה אחת כן מתמלאת בשורה הפנויה האחרונה', () {
      final book = paginate([section(9), section(1)]);

      expect(book.pages.first.columns[0].slices, hasLength(2));
      expect(book.pages.first.columns[1].isEmpty, isTrue);
    });

    test('כלל שכובה מאפשר שבירה בשורה בודדת', () {
      final book = paginate(
        [section(9), section(5)],
        rules: const PaginationRules(
          minLinesToStart: 1,
          minLinesToCarry: 1,
        ),
      );

      expect(book.pages.first.columns[0].slices, hasLength(2));
      expect(
        book.pages.first.columns[0].slices.last.continuesNext,
        isTrue,
      );
    });
  });

  group('כותרות', () {
    test('כותרת אינה נשארת לבד בתחתית הטור', () {
      // 9 שורות תוכן, כותרת בת שורה, ואחריה סעיף ארוך: לכותרת יש מקום אבל
      // לשורות שמתחתיה אין.
      final book = paginate(
        [section(9), section(1), section(5)],
        headings: {1},
      );

      expect(book.pages.first.columns[0].slices, hasLength(1));
      expect(
        book.pages.first.columns[1].slices.map((s) => s.sourceIndex),
        [1, 2],
      );
    });

    test('כותרת עם מקום לשורות שמתחתיה נשארת במקומה', () {
      final book = paginate(
        [section(5), section(1), section(3)],
        headings: {1},
      );

      expect(
        book.pages.first.columns[0].slices.map((s) => s.sourceIndex),
        [0, 1, 2],
      );
    });

    test('כותרת אינה נשארת לבד כשקיצור-האלמנה יכרסם את השורות שמתחתיה', () {
      // 7 שורות + כותרת → נשארות 2 שורות. הסעיף הבא בן 3 שורות, ולכן
      // _withoutWidow יקצר ל-1 כדי לא להשאיר שורה בודדת — פחות מהמינימום
      // שהכותרת דורשת.
      final book = paginate(
        [section(7), section(1), section(3)],
        headings: {1},
      );

      expect(book.pages.first.columns[0].slices, hasLength(1));
      expect(
        book.pages.first.columns[1].slices.map((s) => s.sourceIndex),
        [1, 2],
      );
    });

    test('כותרת אינה נשארת לבד כש-minLinesToStart גדול מהמקום שנשאר', () {
      // 8 שורות + כותרת → נשארת שורה אחת, אבל סעיף חייב להתחיל ב-3 שורות
      // לפחות, ולכן הוא כולו יידחה והכותרת תישאר לבדה.
      final book = paginate(
        [section(8), section(1), section(5)],
        headings: {1},
        rules: const PaginationRules(
          minLinesToStart: 3,
          minLinesToCarry: 1,
          minLinesAfterHeading: 1,
        ),
      );

      expect(book.pages.first.columns[0].slices, hasLength(1));
      expect(
        book.pages.first.columns[1].slices.map((s) => s.sourceIndex),
        [1, 2],
      );
    });

    test('סעיף ריק אחרי כותרת אינו נחשב כמצטרף אליה', () {
      final book = paginate(
        [section(9), section(1), '', section(5)],
        headings: {1},
      );

      expect(book.pages.first.columns[0].slices, hasLength(1));
      expect(
        book.pages.first.columns[1].slices.map((s) => s.sourceIndex),
        [1, 3],
      );
    });

    test('סעיף בלתי נמדד אחרי כותרת מזיז את הכותרת', () {
      // סעיף בלתי נמדד פותח טור לעצמו, ולכן הכותרת הייתה נשארת לבדה.
      final content = [section(9), section(1), section(2)];
      final book = paginate(
        content,
        headings: {1},
        spanOverride: (index) => index == 2
            ? const TextSpan(
                children: [WidgetSpan(child: SizedBox(width: 5, height: 5))],
              )
            : TextSpan(text: content[index], style: style),
      );

      expect(book.pages.first.columns[0].slices, hasLength(1));
      expect(
        book.pages.first.columns[1].slices.map((s) => s.sourceIndex),
        contains(1),
      );
    });

    test('כותרת בסוף הספר אינה זזה — אין מה לשמור איתה', () {
      final book = paginate([section(9), section(1)], headings: {1});

      expect(book.pages.first.columns[0].slices, hasLength(2));
    });

    test('כותרת אינה נשברת בין טורים', () {
      final book = paginate([section(8), section(4)], headings: {1});

      expect(book.pages.first.columns[0].slices, hasLength(1));
      expect(book.pages.first.columns[1].slices.single.sourceIndex, 1);
      expect(
        book.pages.first.columns[1].slices.single.continuesNext,
        isFalse,
      );
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
      expect(book.pages.first.columns[0].slices, hasLength(1));
      expect(book.pages.first.columns[1].isEmpty, isTrue);
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
      final columns = book.pages.expand((page) => page.columns).toList();

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

      final columns = book.pages.expand((page) => page.columns).toList();
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
      final engine = engineFor(List.generate(4, (_) => section(2)));

      expect(engine.progress, 0);
      engine.run(shouldStop: () => engine.sectionsDone >= 2);
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
