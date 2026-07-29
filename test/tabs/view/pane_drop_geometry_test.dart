import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/view/pane_drop_geometry.dart';

void main() {
  const size = Size(400, 300);

  PaneDropPosition at(
    double x,
    double y, {
    TextDirection td = TextDirection.rtl,
  }) {
    return dropPositionFor(
      localPosition: Offset(x, y),
      size: size,
      textDirection: td,
    );
  }

  group('אזורי הפלה ב-RTL', () {
    test('מרכז החלונית הוא אזור החלפה', () {
      expect(at(200, 150), PaneDropPosition.center);
    });

    test('הקצה הימני הוא start ב-RTL', () {
      expect(at(390, 150), PaneDropPosition.start);
    });

    test('הקצה השמאלי הוא end ב-RTL', () {
      expect(at(10, 150), PaneDropPosition.end);
    });

    test('הקצה העליון והתחתון אינם מושפעים מכיוון הכתיבה', () {
      expect(at(200, 5), PaneDropPosition.top);
      expect(at(200, 295), PaneDropPosition.bottom);
    });
  });

  group('אזורי הפלה ב-LTR', () {
    test('הקצוות האופקיים מתהפכים', () {
      expect(at(10, 150, td: TextDirection.ltr), PaneDropPosition.start);
      expect(at(390, 150, td: TextDirection.ltr), PaneDropPosition.end);
    });

    test('המרכז והקצוות האנכיים זהים', () {
      expect(at(200, 150, td: TextDirection.ltr), PaneDropPosition.center);
      expect(at(200, 5, td: TextDirection.ltr), PaneDropPosition.top);
    });
  });

  group('גבולות אלכסוניים', () {
    test('פינה נפתרת לקצה הקרוב ביותר יחסית, לא לפי סדר בדיקה', () {
      // חלונית רחבה מגובהה: בפינה הימנית-עליונה המרחק היחסי מהקצה
      // העליון קטן מזה שמהימני, ולכן זהו הפיצול המכוון.
      expect(at(360, 6), PaneDropPosition.top);
      // אותה פינה, מעט פנימה אנכית — הקצה הימני קרוב יותר יחסית.
      expect(at(396, 60), PaneDropPosition.start);
    });

    test('פינה סימטרית מדויקת אינה משנה תשובה בין הרצות', () {
      // 10% מכל קצה בשני הצירים — הבחירה חייבת להיות דטרמיניסטית.
      final first = at(40, 30);
      for (var i = 0; i < 5; i++) {
        expect(at(40, 30), first);
      }
    });

    test('מצביע בדיוק על סף האזור נחשב עדיין פיצול', () {
      expect(at(size.width * kPaneDropEdgeFraction, 150), PaneDropPosition.end);
      expect(
        at(size.width * kPaneDropEdgeFraction + 1, 150),
        PaneDropPosition.center,
      );
    });
  });

  group('קלט חריג', () {
    test('גודל אפס אינו קורס ומחזיר מרכז', () {
      expect(
        dropPositionFor(
          localPosition: const Offset(10, 10),
          size: Size.zero,
          textDirection: TextDirection.rtl,
        ),
        PaneDropPosition.center,
      );
    });

    test('מיקום מחוץ לגבולות נצמד לקצה', () {
      expect(at(-50, 150), PaneDropPosition.end);
      expect(at(9999, 150), PaneDropPosition.start);
    });
  });

  group('מלבן החיווי', () {
    Rect preview(
      PaneDropPosition p, {
      TextDirection td = TextDirection.rtl,
    }) => previewRectFor(position: p, size: size, textDirection: td);

    test('מרכז מכסה את כל החלונית', () {
      expect(preview(PaneDropPosition.center), Offset.zero & size);
    });

    test('start ב-RTL הוא החצי הימני', () {
      expect(
        preview(PaneDropPosition.start),
        const Rect.fromLTWH(200, 0, 200, 300),
      );
    });

    test('end ב-RTL הוא החצי השמאלי', () {
      expect(
        preview(PaneDropPosition.end),
        const Rect.fromLTWH(0, 0, 200, 300),
      );
    });

    test('start ב-LTR הוא החצי השמאלי', () {
      expect(
        preview(PaneDropPosition.start, td: TextDirection.ltr),
        const Rect.fromLTWH(0, 0, 200, 300),
      );
    });

    test('עליון ותחתון חוצים אופקית', () {
      expect(
        preview(PaneDropPosition.top),
        const Rect.fromLTWH(0, 0, 400, 150),
      );
      expect(
        preview(PaneDropPosition.bottom),
        const Rect.fromLTWH(0, 150, 400, 150),
      );
    });
  });

  group('התאמה בין אזור ההפלה לציר הפיצול', () {
    test('קצוות אופקיים מפצלים אופקית ואנכיים אנכית', () {
      expect(PaneDropPosition.start.axis, isNotNull);
      expect(PaneDropPosition.center.axis, isNull);
      expect(
        PaneDropPosition.top.axis,
        isNot(PaneDropPosition.start.axis),
      );
    });

    test('start ו-top מכניסים את הנגררת ראשונה', () {
      expect(PaneDropPosition.start.placesIncomingFirst, isTrue);
      expect(PaneDropPosition.top.placesIncomingFirst, isTrue);
      expect(PaneDropPosition.end.placesIncomingFirst, isFalse);
      expect(PaneDropPosition.bottom.placesIncomingFirst, isFalse);
    });
  });
}
