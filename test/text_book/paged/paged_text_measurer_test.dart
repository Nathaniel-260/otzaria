// טסטים למודד הגבהים של תצוגת העמודים.
//
// הטסט הקריטי כאן הוא "התלכדות חיתוך": פסקה שנחתכת בגבול שורה חזותית חייבת
// להישבר בשתי הפרוסות בדיוק כמו במקור. כל תצוגת העמודים נשענת על ההנחה הזו —
// אם היא תישבר, שורות ייחתכו בתחתית העמוד או ייעלמו.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/paged/models/paged_layout_signature.dart';
import 'package:otzaria/text_book/paged/services/paged_text_measurer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const width = 200.0;
  const style = TextStyle(fontSize: 20, height: 1.5);
  const locale = Locale('he', 'IL');

  const measurer = PagedTextMeasurer(
    width: width,
    textScaler: TextScaler.noScaling,
    locale: locale,
  );

  /// טקסט שנשבר לכמה שורות ברוחב הנתון.
  TextSpan wrapping([int groups = 14]) => TextSpan(
    text: List.generate(groups, (i) => 'אבג$i').join(' '),
    style: style,
  );

  /// הגבולות חייבים לרצף את הטקסט: שורה מתחילה בסוף הקודמת, או תו אחד אחריה
  /// כשמפריד ביניהן תו שורה חדשה.
  void expectBoundariesTile(MeasuredParagraph m, String text) {
    expect(m.lineStarts.first, 0);
    for (var i = 0; i < m.lineCount; i++) {
      expect(m.lineEnds[i], greaterThanOrEqualTo(m.lineStarts[i]));
      if (i > 0) {
        expect(
          m.lineStarts[i],
          anyOf(m.lineEnds[i - 1], m.lineEnds[i - 1] + 1),
          reason: 'רצף בשורה $i',
        );
      }
    }
    expect(m.lineEnds.last, text.length);
  }

  group('מדידה בסיסית', () {
    test('טקסט ריק — אפס שורות ואפס גובה', () {
      final result = measurer.measure(const TextSpan(text: '', style: style))!;

      expect(result.lineCount, 0);
      expect(result.totalHeight, 0);
      expect(result.isEmpty, isTrue);
    });

    test('שורה אחת קצרה', () {
      final result = measurer.measure(
        const TextSpan(text: 'אבג', style: style),
      )!;

      expect(result.lineCount, 1);
      expect(result.totalHeight, greaterThan(0));
      expect(result.lineStarts, [0]);
      expect(result.lineEnds, [3]);
    });

    test('טקסט ארוך נשבר לכמה שורות והגבולות מרצפים אותו', () {
      final span = wrapping();
      final result = measurer.measure(span)!;

      expect(result.lineCount, greaterThan(2));
      expectBoundariesTile(
        result,
        span.toPlainText(includeSemanticsLabels: false),
      );
    });

    test('סכום גובהי השורות הוא גובה הפסקה', () {
      final result = measurer.measure(wrapping())!;

      var sum = 0.0;
      for (var i = 0; i < result.lineCount; i++) {
        sum += result.lineOffsets[i + 1] - result.lineOffsets[i];
      }
      expect(sum, closeTo(result.totalHeight, 0.001));
      expect(result.lineOffsets.length, result.lineCount + 1);
    });

    test('שורה חדשה מפורשת שוברת, וסוף השורה אינו כולל אותה', () {
      const text = 'ראשון\nשני\nשלישי';
      final result = measurer.measure(
        const TextSpan(text: text, style: style),
      )!;

      expect(result.lineCount, 3);
      expect(result.lineEnds[0], text.indexOf('\n'));
      expect(result.lineStarts[1], text.indexOf('\n') + 1);
      expectBoundariesTile(result, text);
    });

    test('שורה חדשה בסוף מייצרת שורה חזותית ריקה', () {
      final result = measurer.measure(
        const TextSpan(text: 'ראשון\n', style: style),
      )!;

      expect(result.lineCount, 2);
      expect(result.lineStarts.last, result.lineEnds.last);
    });

    test('כותרת גדולה מקבלת שורה גבוהה מטקסט הגוף', () {
      final body = measurer.measure(
        const TextSpan(text: 'אבג', style: style),
      )!;
      final heading = measurer.measure(
        TextSpan(text: 'אבג', style: style.copyWith(fontSize: 40)),
      )!;

      expect(heading.totalHeight, greaterThan(body.totalHeight));
    });

    test('ספאן עם WidgetSpan אינו נמדד', () {
      const span = TextSpan(
        children: [
          TextSpan(text: 'אבג', style: style),
          WidgetSpan(child: SizedBox(width: 10, height: 10)),
        ],
      );

      expect(spanHasPlaceholder(span), isTrue);
      expect(measurer.measure(span), isNull);
    });
  });

  group('linesFittingFrom', () {
    test('גובה שאינו מספיק לשורה אחת מחזיר אפס', () {
      final result = measurer.measure(wrapping())!;

      expect(result.linesFittingFrom(0, 1), 0);
      expect(result.linesFittingFrom(0, 0), 0);
    });

    test('גובה כל הפסקה מחזיר את כל השורות', () {
      final result = measurer.measure(wrapping())!;

      expect(result.linesFittingFrom(0, result.totalHeight), result.lineCount);
    });

    test('גובה שתי שורות מחזיר שתיים בדיוק', () {
      final result = measurer.measure(wrapping())!;
      final twoLines = result.heightOfFirst(2);

      expect(result.linesFittingFrom(0, twoLines), 2);
      // פחות משתי שורות בפיקסל אחד — נכנסת רק אחת.
      expect(result.linesFittingFrom(0, twoLines - 1), 1);
    });

    test('ספירה מאמצע הפסקה מתייחסת לשורות שאחרי [from]', () {
      final result = measurer.measure(wrapping())!;
      final heightOfLineTwo = result.lineOffsets[3] - result.lineOffsets[2];

      expect(result.linesFittingFrom(2, heightOfLineTwo), 1);
      expect(result.linesFittingFrom(result.lineCount, 10000), 0);
    });

    test('heightFrom משלים את heightOfFirst', () {
      final result = measurer.measure(wrapping())!;

      for (var i = 0; i <= result.lineCount; i++) {
        expect(
          result.heightOfFirst(i) + result.heightFrom(i),
          closeTo(result.totalHeight, 0.001),
        );
      }
    });
  });

  group('התלכדות חיתוך — כל תצוגת העמודים נשענת על זה', () {
    /// חותך בכל גבול שורה ומאמת שהפרוסות נשברות ומודדות כמו המקור.
    void expectSliceConverges(InlineSpan span, {String? label}) {
      final full = measurer.measure(span)!;
      expect(full.lineCount, greaterThan(1), reason: 'צריך יותר משורה אחת');

      for (var k = 1; k < full.lineCount; k++) {
        final head = sliceInlineSpan(span, 0, full.lineEnds[k - 1]);
        final tail = sliceInlineSpan(
          span,
          full.lineStarts[k],
          full.lineEnds.last,
        );
        final why = '${label ?? ''} חיתוך בשורה $k';

        final measuredHead = measurer.measure(head!)!;
        final measuredTail = measurer.measure(tail!)!;

        expect(measuredHead.lineCount, k, reason: '$why — שורות ברישא');
        expect(
          measuredTail.lineCount,
          full.lineCount - k,
          reason: '$why — שורות בסיפא',
        );
        expect(
          measuredHead.totalHeight,
          closeTo(full.heightOfFirst(k), 0.01),
          reason: '$why — גובה הרישא',
        );
        expect(
          measuredTail.totalHeight,
          closeTo(full.heightFrom(k), 0.01),
          reason: '$why — גובה הסיפא',
        );
      }
    }

    test('טקסט שנשבר רק בגלישה', () {
      expectSliceConverges(wrapping(20), label: 'גלישה');
    });

    test('טקסט עם שורות חדשות מפורשות', () {
      expectSliceConverges(
        TextSpan(
          text: List.generate(6, (i) => 'שורה מספר $i עם עוד מילים כאן').join(
            '\n',
          ),
          style: style,
        ),
        label: 'שורות מפורשות',
      );
    });

    test('טקסט עם סגנונות מעורבים בתוך הפסקה', () {
      expectSliceConverges(
        TextSpan(
          style: style,
          children: [
            const TextSpan(text: 'פתיחה רגילה של הפסקה '),
            TextSpan(
              text: 'קטע מודגש וגדול ',
              style: style.copyWith(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const TextSpan(text: 'והמשך רגיל עם עוד מילים כדי לגלוש '),
            TextSpan(
              text: 'וקטע קטן בסוף הפסקה הזאת',
              style: style.copyWith(fontSize: 12),
            ),
          ],
        ),
        label: 'סגנונות מעורבים',
      );
    });
  });

  group('sliceInlineSpan', () {
    test('טווח ריק מחזיר null', () {
      expect(sliceInlineSpan(wrapping(), 5, 5), isNull);
      expect(sliceInlineSpan(wrapping(), 5, 4), isNull);
    });

    test('הטקסט של הפרוסה הוא בדיוק תת-המחרוזת', () {
      final span = wrapping();
      final text = span.toPlainText(includeSemanticsLabels: false);

      final sliced = sliceInlineSpan(span, 4, 12)!;

      expect(
        sliced.toPlainText(includeSemanticsLabels: false),
        text.substring(4, 12),
      );
    });

    test('חיתוך על גבול בין ילדים משמר את שני הסגנונות', () {
      const first = TextStyle(fontSize: 20);
      const second = TextStyle(fontSize: 30);
      const span = TextSpan(
        children: [
          TextSpan(text: 'אבגד', style: first),
          TextSpan(text: 'הוזח', style: second),
        ],
      );

      final sliced = sliceInlineSpan(span, 2, 6)! as TextSpan;

      expect(sliced.toPlainText(includeSemanticsLabels: false), 'גדהו');
      expect((sliced.children![0] as TextSpan).style, first);
      expect((sliced.children![1] as TextSpan).style, second);
    });

    test('recognizer של קישור נשמר בפרוסה', () {
      final recognizer = TapGestureRecognizer();
      addTearDown(recognizer.dispose);
      final span = TextSpan(
        children: [
          const TextSpan(text: 'לפני '),
          TextSpan(text: 'קישור', recognizer: recognizer),
          const TextSpan(text: ' אחרי'),
        ],
      );

      final sliced = sliceInlineSpan(span, 0, 11)! as TextSpan;
      final linkChild = sliced.children!.whereType<TextSpan>().firstWhere(
        (child) => child.text == 'קישור',
      );

      expect(linkChild.recognizer, same(recognizer));
    });

    test('ילד שכולו מחוץ לטווח אינו מסיט את החיתוך', () {
      const span = TextSpan(
        children: [
          TextSpan(text: 'ראשון'),
          TextSpan(text: 'שני'),
          TextSpan(text: 'שלישי'),
        ],
      );

      // "שלישי" מתחיל בהיסט 8.
      final sliced = sliceInlineSpan(span, 8, 13)!;

      expect(sliced.toPlainText(includeSemanticsLabels: false), 'שלישי');
    });
  });

  group('התלכדות מדידה↔ציור', () {
    Future<double> paintedHeight(WidgetTester tester, InlineSpan span) async {
      await tester.pumpWidget(
        Center(
          child: SizedBox(
            width: width,
            child: RichText(
              text: span,
              locale: locale,
              textAlign: TextAlign.justify,
              textDirection: TextDirection.rtl,
              textScaler: TextScaler.noScaling,
              textWidthBasis: kPagedTextWidthBasis,
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(RichText)).height;
    }

    testWidgets('גובה פסקה שלמה זהה בציור ובמדידה', (tester) async {
      final span = wrapping(20);

      expect(
        await paintedHeight(tester, span),
        closeTo(measurer.measure(span)!.totalHeight, 0.01),
      );
    });

    testWidgets('גובה פרוסה זהה לגובה שהעימוד הקציב לה', (tester) async {
      final span = wrapping(20);
      final full = measurer.measure(span)!;
      final cut = full.lineCount ~/ 2;

      final head = sliceInlineSpan(span, 0, full.lineEnds[cut - 1])!;
      final tail = sliceInlineSpan(
        span,
        full.lineStarts[cut],
        full.lineEnds.last,
      )!;

      expect(
        await paintedHeight(tester, head),
        closeTo(full.heightOfFirst(cut), 0.01),
      );
      expect(
        await paintedHeight(tester, tail),
        closeTo(full.heightFrom(cut), 0.01),
      );
    });
  });
}
