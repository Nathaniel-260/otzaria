// טסטים לזום תצוגת העמודים.
//
// הזום מגדיל את העמוד ולא את הגופן, ולכן הוא אינו נוגע בעימוד. כאן נבדקת
// אריתמטיקת הצעדים והחסימה לטווח בלבד.

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/models/text_book_view_mode.dart';
import 'package:otzaria/text_book/paged/models/paged_zoom.dart';

void main() {
  group('חסימה לטווח', () {
    test('ערך בתוך הטווח נשמר', () {
      expect(clampPagedZoom(1.0), 1.0);
      expect(clampPagedZoom(2.4), 2.4);
    });

    test('ערך מחוץ לטווח נחסם', () {
      expect(clampPagedZoom(0.1), kMinPagedZoom);
      expect(clampPagedZoom(99), kMaxPagedZoom);
      expect(clampPagedZoom(-5), kMinPagedZoom);
    });

    test('NaN חוזר לברירת המחדל', () {
      // טאב שמור עם ערך פגום לא אמור להשאיר את התצוגה בגודל לא מוגדר.
      expect(clampPagedZoom(double.nan), kDefaultPagedZoom);
    });

    test('אינסוף נחסם ואינו מחזיר אינסוף', () {
      expect(clampPagedZoom(double.infinity), kMaxPagedZoom);
      expect(clampPagedZoom(double.negativeInfinity), kMinPagedZoom);
    });
  });

  group('צעד', () {
    test('הגדלה והקטנה בצעד אחד', () {
      expect(steppedPagedZoom(1.0, 1), closeTo(1.0 + kPagedZoomStep, 1e-9));
      expect(steppedPagedZoom(1.0, -1), closeTo(1.0 - kPagedZoomStep, 1e-9));
    });

    test('הצעדים נשארים נקיים אחרי צבירה', () {
      // 1.1 + 0.1 אינו 1.2 בדיוק ב-double; בלי עיגול הערכים היו מתלכלכים.
      var zoom = kDefaultPagedZoom;
      for (var i = 0; i < 5; i++) {
        zoom = steppedPagedZoom(zoom, 1);
      }
      expect(zoom, closeTo(1.5, 1e-9));

      for (var i = 0; i < 5; i++) {
        zoom = steppedPagedZoom(zoom, -1);
      }
      expect(zoom, closeTo(1.0, 1e-9));
    });

    test('הצעד נעצר בקצוות ואינו חורג', () {
      var zoom = kMaxPagedZoom;
      zoom = steppedPagedZoom(zoom, 1);
      expect(zoom, kMaxPagedZoom);

      zoom = kMinPagedZoom;
      zoom = steppedPagedZoom(zoom, -1);
      expect(zoom, kMinPagedZoom);
    });

    test('צעד מערך פגום מתחיל מברירת המחדל', () {
      expect(
        steppedPagedZoom(double.nan, 1),
        closeTo(kDefaultPagedZoom + kPagedZoomStep, 1e-9),
      );
    });
  });

  group('ההעדפה "מפרשים בצד/מתחת"', () {
    test('חלה על שתי תצוגות המפרשים בלבד', () {
      // בצורת הדף ובתצוגת העמודים אין מפרשים בצד או מתחת. מעבר אליהן היה
      // דורס את ההעדפה, וטעינתה הייתה מוציאה את המשתמש מהתצוגה שבחר.
      expect(TextBookViewMode.split.usesCommentaryLayoutPreference, isTrue);
      expect(TextBookViewMode.combined.usesCommentaryLayoutPreference, isTrue);
      expect(
        TextBookViewMode.pageShape.usesCommentaryLayoutPreference,
        isFalse,
      );
      expect(TextBookViewMode.paged.usesCommentaryLayoutPreference, isFalse);
    });
  });
}
