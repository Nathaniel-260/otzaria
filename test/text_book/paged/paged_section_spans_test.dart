import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/paged/view/paged_section_spans.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

void main() {
  const style = TextStyle(fontSize: 18, fontFamily: 'FrankRuhlCLM');

  PagedSectionSpanBuilder builderFor(
    List<String> content, {
    RenderSettings settings = const RenderSettings(),
  }) => PagedSectionSpanBuilder(
    content: content,
    settings: settings,
    baseStyle: style,
  );

  String plain(InlineSpan span) =>
      span.toPlainText(includeSemanticsLabels: false);

  group('בניית ספאן', () {
    test('סעיף עם טקסט מחזיר ספאן עם אותו טקסט', () {
      final span = builderFor(['בראשית ברא אלהים']).spanFor(0)!;

      expect(plain(span), contains('בראשית ברא אלהים'));
      expect((span as TextSpan).style, style);
    });

    test('סעיף ריק או רווחים בלבד מחזיר null', () {
      final builder = builderFor(['', '   ', '\n']);

      expect(builder.spanFor(0), isNull);
      expect(builder.spanFor(1), isNull);
      expect(builder.spanFor(2), isNull);
    });

    test('אינדקס מחוץ לתחום מחזיר null', () {
      final builder = builderFor(['אבג']);

      expect(builder.spanFor(-1), isNull);
      expect(builder.spanFor(1), isNull);
    });

    test('כותרת נשברת לשורה משלה ומקבלת גודל גדול יותר', () {
      final span =
          builderFor(['<h2>כותרת</h2>המשך הטקסט']).spanFor(0)! as TextSpan;

      expect(plain(span), 'כותרת\nהמשך הטקסט');
    });

    test('הסרת ניקוד מוחלת על הטקסט', () {
      const withNikud = 'בְּרֵאשִׁית';

      final kept = builderFor([withNikud]).spanFor(0)!;
      final removed = builderFor(
        [withNikud],
        settings: const RenderSettings(removeNikud: true),
      ).spanFor(0)!;

      expect(plain(removed).length, lessThan(plain(kept).length));
      expect(plain(removed), contains('בראשית'));
    });

    test('תגי עיצוב אינם מופיעים בטקסט', () {
      final span = builderFor(['<b>מודגש</b> ורגיל']).spanFor(0)!;

      expect(plain(span), 'מודגש ורגיל');
    });
  });

  group('מטמון', () {
    test('קריאה חוזרת לאותו סעיף אינה בונה מחדש', () {
      final builder = builderFor(['אבג', 'דהו']);

      builder.spanFor(0);
      builder.spanFor(1);
      builder.spanFor(0);
      builder.spanFor(1);

      expect(builder.buildCount, 2);
    });

    test('סעיף שהוחזר כ-null גם הוא ממוזכר', () {
      final builder = builderFor(['']);

      builder.spanFor(0);
      builder.spanFor(0);

      expect(builder.buildCount, 1);
    });

    test('clear מרוקן את המטמון', () {
      final builder = builderFor(['אבג']);
      builder.spanFor(0);

      builder.clear();
      builder.spanFor(0);

      expect(builder.buildCount, 1);
    });

    test('מטמון גדול מהתקרה אינו גדל בלי גבול', () {
      final builder = builderFor(List.generate(400, (i) => 'סעיף $i'));

      for (var i = 0; i < 400; i++) {
        builder.spanFor(i);
      }
      // הסעיף הראשון נדחק, ולכן ייבנה מחדש.
      builder.spanFor(0);

      expect(builder.buildCount, 401);
    });
  });

  group('זיהוי כותרת', () {
    test('שורת h2 מזוהה', () {
      expect(builderFor(['<h2>פרק א</h2>']).isHeading(0), isTrue);
    });

    test('טקסט רגיל אינו כותרת', () {
      expect(builderFor(['בראשית ברא']).isHeading(0), isFalse);
    });

    test('אינדקס מחוץ לתחום אינו כותרת', () {
      expect(builderFor(['אבג']).isHeading(5), isFalse);
    });
  });
}
