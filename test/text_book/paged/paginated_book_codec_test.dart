import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/paged/models/page_geometry.dart';
import 'package:otzaria/text_book/paged/models/paginated_book.dart';
import 'package:otzaria/text_book/paged/repository/paginated_book_codec.dart';

void main() {
  final geometry = PageGeometry.paper(PagePaperSize.a4);

  PaginatedBook bookOf(List<BookPage> pages, {int sectionCount = 50}) =>
      PaginatedBook(
        pages: pages,
        geometry: geometry,
        sectionCount: sectionCount,
      );

  BookPage page(
    int number,
    List<List<PageSlice>> columns, {
    required int first,
    required int last,
  }) => BookPage(
    number: number,
    columns: columns.map(PageColumn.new).toList(),
    firstSourceIndex: first,
    lastSourceIndex: last,
  );

  group('הלוך וחזור', () {
    test('ספר ריק', () {
      final book = bookOf(const [], sectionCount: 0);

      final decoded = decodePaginatedBook(
        encodePaginatedBook(book),
        geometry,
      )!;

      expect(decoded.pages, isEmpty);
      expect(decoded.sectionCount, 0);
      expect(decoded.geometry, geometry);
    });

    test('עמוד אחד, שני טורים', () {
      final book = bookOf([
        page(
          1,
          [
            const [PageSlice(sourceIndex: 0, charStart: 0, charEnd: 40)],
            const [PageSlice(sourceIndex: 1, charStart: 0, charEnd: 90)],
          ],
          first: 0,
          last: 1,
        ),
      ]);

      final decoded = decodePaginatedBook(
        encodePaginatedBook(book),
        geometry,
      )!;

      expect(decoded.pages, book.pages);
    });

    test('טור ריק נשמר כטור ריק ולא נעלם', () {
      final book = bookOf([
        page(
          1,
          [
            const [PageSlice(sourceIndex: 0, charStart: 0, charEnd: 10)],
            const [],
          ],
          first: 0,
          last: 0,
        ),
      ]);

      final decoded = decodePaginatedBook(
        encodePaginatedBook(book),
        geometry,
      )!;

      expect(decoded.pages.first.columns, hasLength(2));
      expect(decoded.pages.first.columns[1].isEmpty, isTrue);
    });

    test('דגלי המשך נשמרים לכל צירוף', () {
      final book = bookOf([
        page(
          1,
          [
            const [
              PageSlice(sourceIndex: 0, charStart: 0, charEnd: 5),
              PageSlice(
                sourceIndex: 1,
                charStart: 0,
                charEnd: 5,
                continuesNext: true,
              ),
              PageSlice(
                sourceIndex: 2,
                charStart: 5,
                charEnd: 9,
                continuesPrevious: true,
              ),
              PageSlice(
                sourceIndex: 3,
                charStart: 5,
                charEnd: 9,
                continuesPrevious: true,
                continuesNext: true,
              ),
            ],
          ],
          first: 0,
          last: 3,
        ),
      ]);

      final decoded = decodePaginatedBook(
        encodePaginatedBook(book),
        geometry,
      )!;

      expect(decoded.pages.first.columns[0].slices, book.pages[0].slices);
    });

    test('מספרי העמודים והסעיפים בקצוות נשמרים', () {
      final book = bookOf([
        page(
          1,
          [
            const [PageSlice(sourceIndex: 4, charStart: 0, charEnd: 5)],
          ],
          first: 4,
          last: 7,
        ),
        page(
          2,
          [
            const [PageSlice(sourceIndex: 7, charStart: 5, charEnd: 9)],
          ],
          first: 7,
          last: 7,
        ),
      ]);

      final decoded = decodePaginatedBook(
        encodePaginatedBook(book),
        geometry,
      )!;

      expect(decoded.pages.map((p) => p.number), [1, 2]);
      expect(decoded.pages[0].firstSourceIndex, 4);
      expect(decoded.pages[0].lastSourceIndex, 7);
      expect(decoded.pages[1].firstSourceIndex, 7);
    });

    test('ספר גדול נשמר ונקרא במלואו', () {
      final pages = List.generate(
        400,
        (i) => page(
          i + 1,
          [
            List.generate(
              8,
              (s) => PageSlice(
                sourceIndex: i * 10 + s,
                charStart: s * 100,
                charEnd: s * 100 + 90,
                continuesNext: s.isEven,
              ),
            ),
            const [],
          ],
          first: i * 10,
          last: i * 10 + 7,
        ),
      );
      final book = bookOf(pages, sectionCount: 4000);

      final encoded = encodePaginatedBook(book);
      final decoded = decodePaginatedBook(encoded, geometry)!;

      expect(decoded.pages, book.pages);
      expect(decoded.pages.last.columns[0].slices.last.charEnd, 790);
    });

    test('הניווט עובד גם על עימוד שנקרא מהמטמון', () {
      final book = bookOf([
        page(
          1,
          [
            const [PageSlice(sourceIndex: 0, charStart: 0, charEnd: 5)],
          ],
          first: 0,
          last: 2,
        ),
        page(
          2,
          [
            const [PageSlice(sourceIndex: 3, charStart: 0, charEnd: 5)],
          ],
          first: 3,
          last: 9,
        ),
      ]);

      final decoded = decodePaginatedBook(
        encodePaginatedBook(book),
        geometry,
      )!;

      expect(decoded.pageNumberOfSource(1), 1);
      expect(decoded.pageNumberOfSource(5), 2);
    });
  });

  group('שדות מחוץ לטווח נדחים', () {
    /// מחליף שלם בודד במקום [intIndex] בזרם המקודד של [book].
    String tamper(PaginatedBook book, int intIndex, int value) {
      final bytes = base64Decode(encodePaginatedBook(book));
      ByteData.sublistView(bytes).setInt32(intIndex * 4, value, Endian.little);
      return base64Encode(bytes);
    }

    /// ספר בן עמוד אחד עם פרוסה אחת, 3 סעיפים.
    PaginatedBook simple() => bookOf(
      [
        page(
          1,
          [
            const [PageSlice(sourceIndex: 1, charStart: 0, charEnd: 5)],
          ],
          first: 1,
          last: 1,
        ),
      ],
      sectionCount: 3,
    );

    /// מיקומי השלמים בזרם: version, sectionCount, pageCount, first, last, …
    const firstSourceAt = 3;
    const lastSourceAt = 4;
    const sliceSourceAt = 7;
    const charStartAt = 8;
    const charEndAt = 9;

    test('הספר הבסיסי עצמו מפוענח — הכיול תקין', () {
      expect(
        decodePaginatedBook(encodePaginatedBook(simple()), geometry),
        isNotNull,
      );
    });

    test('sourceIndex של פרוסה מעל sectionCount', () {
      // בלי האימות זה היה מפוענח לספר "תקין" שבו הניווט מגיע לעמוד שרירותי.
      expect(
        decodePaginatedBook(tamper(simple(), sliceSourceAt, 9999), geometry),
        isNull,
      );
    });

    test('sourceIndex שלילי', () {
      expect(
        decodePaginatedBook(tamper(simple(), sliceSourceAt, -1), geometry),
        isNull,
      );
    });

    test('charStart שלילי', () {
      expect(
        decodePaginatedBook(tamper(simple(), charStartAt, -500), geometry),
        isNull,
      );
    });

    test('charEnd קטן מ-charStart', () {
      expect(
        decodePaginatedBook(tamper(simple(), charEndAt, -1), geometry),
        isNull,
      );
    });

    test('firstSourceIndex שלילי', () {
      expect(
        decodePaginatedBook(tamper(simple(), firstSourceAt, -3), geometry),
        isNull,
      );
    });

    test('lastSourceIndex מעל sectionCount', () {
      expect(
        decodePaginatedBook(tamper(simple(), lastSourceAt, 500), geometry),
        isNull,
      );
    });

    test('lastSourceIndex קטן מ-firstSourceIndex', () {
      expect(
        decodePaginatedBook(tamper(simple(), lastSourceAt, 0), geometry),
        isNull,
      );
    });

    test('זבל בזנב הזרם', () {
      final bytes = base64Decode(encodePaginatedBook(simple()));
      final withTail = Uint8List(bytes.length + 4)
        ..setRange(0, bytes.length, bytes);

      expect(decodePaginatedBook(base64Encode(withTail), geometry), isNull);
    });
  });

  group('קלט שאינו תקין מוחזר כ-null', () {
    test('מחרוזת שאינה base64', () {
      expect(decodePaginatedBook('לא base64 בכלל!!', geometry), isNull);
    });

    test('מחרוזת ריקה', () {
      expect(decodePaginatedBook('', geometry), isNull);
    });

    test('אורך שאינו כפולה של ארבע', () {
      expect(
        decodePaginatedBook(
          base64Encode(Uint8List.fromList(List.filled(13, 1))),
          geometry,
        ),
        isNull,
      );
    });

    test('גרסת פורמט אחרת', () {
      final data = ByteData(12)
        ..setInt32(0, kPaginatedBookCodecVersion + 1, Endian.little)
        ..setInt32(4, 10, Endian.little)
        ..setInt32(8, 0, Endian.little);

      expect(
        decodePaginatedBook(
          base64Encode(data.buffer.asUint8List()),
          geometry,
        ),
        isNull,
      );
    });

    test('רשומה שנקטעה באמצע', () {
      final book = bookOf([
        page(
          1,
          [
            const [PageSlice(sourceIndex: 0, charStart: 0, charEnd: 5)],
            const [],
          ],
          first: 0,
          last: 0,
        ),
      ]);
      final bytes = base64Decode(encodePaginatedBook(book));

      final truncated = base64Encode(
        Uint8List.sublistView(bytes, 0, bytes.length - 8),
      );

      expect(decodePaginatedBook(truncated, geometry), isNull);
    });

    test('מונה עמודים מופרך אינו מקצה זיכרון', () {
      final data = ByteData(12)
        ..setInt32(0, kPaginatedBookCodecVersion, Endian.little)
        ..setInt32(4, 10, Endian.little)
        ..setInt32(8, 1 << 28, Endian.little);

      expect(
        decodePaginatedBook(
          base64Encode(data.buffer.asUint8List()),
          geometry,
        ),
        isNull,
      );
    });

    test('מונה פרוסות מופרך אינו מקצה זיכרון', () {
      final data = ByteData(28)
        ..setInt32(0, kPaginatedBookCodecVersion, Endian.little)
        ..setInt32(4, 10, Endian.little)
        ..setInt32(8, 1, Endian.little)
        ..setInt32(12, 0, Endian.little)
        ..setInt32(16, 0, Endian.little)
        ..setInt32(20, 1, Endian.little)
        ..setInt32(24, 1 << 26, Endian.little);

      expect(
        decodePaginatedBook(
          base64Encode(data.buffer.asUint8List()),
          geometry,
        ),
        isNull,
      );
    });
  });
}
