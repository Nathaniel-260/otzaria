// טסטים ל-`applyBlockStyles` של `buildInlineHtmlSpans`.
//
// הדגל הזה נוסף כדי שתצוגת העמודים תוכל למדוד כותרות ובלוקים באותו InlineSpan
// שבו הם מצוירים. הוא **חייב** להישאר כבוי במצב הקריאה הרציף — שם כותרת היא
// סגמנט נפרד שלא עובר בנתיב הזה, והפעלתו שם הייתה משנה את הרינדור הקיים.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';

/// הסגנון של הספאן הראשון שיש לו טקסט.
TextStyle? _firstStyle(List<InlineSpan> spans) {
  for (final span in spans) {
    if (span is TextSpan) {
      if (span.text != null && span.text!.isNotEmpty) return span.style;
      final children = span.children;
      if (children != null) {
        final nested = _firstStyle(children);
        if (nested != null) return nested;
      }
    }
  }
  return null;
}

String _plain(List<InlineSpan> spans) =>
    TextSpan(children: spans).toPlainText();

void main() {
  // גופן ללא face בולד נפרד וללא ציר משקל — הכותרת מקבלת bold רגיל.
  const base = TextStyle(fontSize: 20, fontFamily: 'SomePlainFont');

  group('applyBlockStyles כבוי — נועל את התנהגות המצב הרציף', () {
    test('כותרת h2 נשארת בגודל הטקסט ובלי הדגשה', () {
      final style = _firstStyle(buildInlineHtmlSpans('<h2>כותרת</h2>', base));

      expect(style?.fontSize ?? base.fontSize, 20);
      expect(style?.fontWeight, isNot(FontWeight.bold));
    });

    test('תגי בלוק אינם שוברים שורה', () {
      expect(
        _plain(buildInlineHtmlSpans('<p>ראשון</p><p>שני</p>', base)),
        'ראשוןשני',
      );
    });
  });

  group('applyBlockStyles מופעל', () {
    test('h1–h6 מקבלים את מכפילי הגודל של flutter_widget_from_html', () {
      const scales = {
        'h1': 2.0,
        'h2': 1.5,
        'h3': 1.17,
        'h4': 1.0,
        'h5': 0.83,
        'h6': 0.67,
      };

      for (final entry in scales.entries) {
        final spans = buildInlineHtmlSpans(
          '<${entry.key}>כותרת</${entry.key}>',
          base,
          applyBlockStyles: true,
        );

        expect(
          _firstStyle(spans)?.fontSize,
          closeTo(20 * entry.value, 0.001),
          reason: entry.key,
        );
      }
    });

    test('כותרת מודגשת בגופן ללא face בולד נפרד', () {
      final style = _firstStyle(
        buildInlineHtmlSpans('<h3>כותרת</h3>', base, applyBlockStyles: true),
      );

      expect(style?.fontWeight, FontWeight.bold);
    });

    test('כותרת ב-FrankRuhlCLM מקבלת w400 — ל-face הבולד ציור אות אחר', () {
      final style = _firstStyle(
        buildInlineHtmlSpans(
          '<h3>כותרת</h3>',
          const TextStyle(fontSize: 20, fontFamily: 'FrankRuhlCLM'),
          applyBlockStyles: true,
        ),
      );

      expect(style?.fontWeight, FontWeight.w400);
    });

    test('תגי בלוק שוברים שורה ביניהם', () {
      expect(
        _plain(
          buildInlineHtmlSpans(
            '<p>ראשון</p><p>שני</p>',
            base,
            applyBlockStyles: true,
          ),
        ),
        'ראשון\nשני',
      );
    });

    test('הבלוק הראשון אינו מוסיף שורה ריקה בראש הפסקה', () {
      final text = _plain(
        buildInlineHtmlSpans('<p>יחיד</p>', base, applyBlockStyles: true),
      );

      expect(text, 'יחיד');
      expect(text.startsWith('\n'), isFalse);
    });

    test('פריטי רשימה נפרדים לשורות', () {
      expect(
        _plain(
          buildInlineHtmlSpans(
            '<ul><li>אחד</li><li>שניים</li></ul>',
            base,
            applyBlockStyles: true,
          ),
        ),
        'אחד\nשניים',
      );
    });

    test('טקסט inline רגיל אינו נשבר', () {
      expect(
        _plain(
          buildInlineHtmlSpans(
            'רגיל <b>מודגש</b> והמשך',
            base,
            applyBlockStyles: true,
          ),
        ),
        'רגיל מודגש והמשך',
      );
    });
  });
}
