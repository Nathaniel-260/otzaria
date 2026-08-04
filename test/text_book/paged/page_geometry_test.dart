import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/paged/models/page_geometry.dart';

void main() {
  group('PageGeometry', () {
    test('A4 מתורגם לפיקסלים לוגיים לפי 96dpi', () {
      const a4 = PagePaperSize.a4;

      expect(a4.widthPx, closeTo(210 * 96 / 25.4, 0.001));
      expect(a4.heightPx, closeTo(297 * 96 / 25.4, 0.001));
    });

    test('רוחב הטור מחסיר שוליים ומרווח, ומחלק במספר הטורים', () {
      final geometry = PageGeometry.paper(
        PagePaperSize.a4,
        columns: 2,
        marginMm: 18,
        columnGapMm: 7,
      );

      final expectedContent = (210 - 2 * 18) * kMmToLogicalPx;
      expect(geometry.contentWidth, closeTo(expectedContent, 0.001));
      expect(
        geometry.columnWidth,
        closeTo((expectedContent - 7 * kMmToLogicalPx) / 2, 0.001),
      );
    });

    test('בטור אחד אין מרווח להחסיר — הטור הוא כל רוחב התוכן', () {
      final geometry = PageGeometry.paper(PagePaperSize.a4, columns: 1);

      expect(geometry.columnWidth, closeTo(geometry.contentWidth, 0.001));
    });

    test('גובה התוכן מחסיר גם את אזור מספר העמוד', () {
      final geometry = PageGeometry.paper(
        PagePaperSize.a4,
        marginMm: 18,
        headerMm: 8,
      );

      expect(
        geometry.contentHeight,
        closeTo((297 - 2 * 18 - 8) * kMmToLogicalPx, 0.001),
      );
    });

    test('הגובה הכולל הוא גובה התוכן כפול מספר הטורים', () {
      final geometry = PageGeometry.paper(PagePaperSize.a4, columns: 2);

      expect(
        geometry.totalColumnHeight,
        closeTo(geometry.contentHeight * 2, 0.001),
      );
    });

    test('singleColumn שומר על גודל העמוד ומשנה רק את מספר הטורים', () {
      final two = PageGeometry.paper(PagePaperSize.a4, columns: 2);
      final one = two.singleColumn;

      expect(one.columns, 1);
      expect(one.width, two.width);
      expect(one.height, two.height);
      expect(one.margins, two.margins);
      // הטור מתרחב לכל רוחב התוכן — זו כל ההשפעה של המסך הצר.
      expect(one.columnWidth, greaterThan(two.columnWidth));
    });

    test('singleColumn על גאומטריה בת טור אחד מחזיר את אותו מופע', () {
      final one = PageGeometry.paper(PagePaperSize.a4, columns: 1);

      expect(identical(one.singleColumn, one), isTrue);
    });

    test('הקו המפריד יושב באמצע אזור התוכן', () {
      final two = PageGeometry.paper(PagePaperSize.a4, columns: 2);

      // אמצע מדויק = שני הטורים שווים ברוחבם.
      expect(two.columnRuleCenter(0), closeTo(two.contentWidth / 2, 0.001));
    });

    test('גאומטריות זהות שוות ומייצרות אותו מפתח', () {
      final first = PageGeometry.paper(PagePaperSize.a4);
      final second = PageGeometry.paper(PagePaperSize.a4);

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.cacheKey, second.cacheKey);
    });

    test('כל מידה שמשפיעה על פריסה משנה את המפתח', () {
      final base = PageGeometry.paper(PagePaperSize.a4);
      final variants = <String, PageGeometry>{
        'width': base.copyWith(width: base.width + 1),
        'height': base.copyWith(height: base.height + 1),
        'margins': base.copyWith(margins: const EdgeInsets.all(4)),
        'columns': base.copyWith(columns: 1),
        'columnGap': base.copyWith(columnGap: base.columnGap + 1),
        'headerHeight': base.copyWith(headerHeight: base.headerHeight + 1),
      };

      for (final entry in variants.entries) {
        expect(
          entry.value.cacheKey,
          isNot(base.cacheKey),
          reason: entry.key,
        );
        expect(entry.value, isNot(base), reason: entry.key);
      }
    });

    test('נייר Letter נבדל מ-A4', () {
      expect(
        PageGeometry.paper(PagePaperSize.letter).cacheKey,
        isNot(PageGeometry.paper(PagePaperSize.a4).cacheKey),
      );
    });

    test('מספר טורים אחר מ-1 או 2 נחסם', () {
      expect(
        () => PageGeometry.paper(PagePaperSize.a4, columns: 3),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
