// בדיקות שכבת המטמון של תצוגת העמודים מול cache.db אמיתי בתיקייה זמנית.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/text_book/paged/models/page_geometry.dart';
import 'package:otzaria/text_book/paged/models/paged_layout_signature.dart';
import 'package:otzaria/text_book/paged/models/paginated_book.dart';
import 'package:otzaria/text_book/paged/repository/paged_layout_cache.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;
  late PagedLayoutCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('paged-layout-cache-');
    database = MyDatabase.withPath(path.join(tempDir.path, 'cache.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();
    cache = PagedLayoutCache(repositoryProvider: () async => repository);
  });

  tearDown(() async {
    database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  final geometry = PageGeometry.paper(PagePaperSize.a4);
  const content = ['סעיף ראשון', 'סעיף שני', 'סעיף שלישי'];

  PagedLayoutSignature signature({
    String bookId = 'ספר בדיקה',
    List<String> lines = content,
    RenderSettings settings = const RenderSettings(),
    PageGeometry? pageGeometry,
  }) => PagedLayoutSignature.from(
    bookId: bookId,
    content: lines,
    geometry: pageGeometry ?? geometry,
    settings: settings,
    textScaler: TextScaler.noScaling,
    locale: const Locale('he', 'IL'),
  );

  PaginatedBook bookOf({int sectionCount = 3}) => PaginatedBook(
    pages: [
      BookPage(
        number: 1,
        bands: const [
          ColumnsBand([
            PageColumn([PageSlice(sourceIndex: 0, charStart: 0, charEnd: 10)]),
            PageColumn([
              PageSlice(
                sourceIndex: 1,
                charStart: 0,
                charEnd: 8,
                continuesNext: true,
              ),
            ]),
          ]),
        ],
        firstSourceIndex: 0,
        lastSourceIndex: 1,
      ),
      BookPage(
        number: 2,
        bands: const [
          ColumnsBand([
            PageColumn([
              PageSlice(
                sourceIndex: 1,
                charStart: 8,
                charEnd: 12,
                continuesPrevious: true,
              ),
              PageSlice(sourceIndex: 2, charStart: 0, charEnd: 11),
            ]),
            PageColumn([]),
          ]),
        ],
        firstSourceIndex: 1,
        lastSourceIndex: 2,
      ),
    ],
    geometry: geometry,
    sectionCount: sectionCount,
  );

  group('שמירה וטעינה', () {
    test('עימוד שנשמר נטען חזרה זהה', () async {
      final key = signature();
      final book = bookOf();

      await cache.save(key, book);
      final loaded = await cache.load(key);

      expect(loaded, isNotNull);
      expect(loaded!.pages, book.pages);
      expect(loaded.sectionCount, 3);
      expect(loaded.geometry, geometry);
    });

    test('חתימה שלא נשמרה מחזירה null', () async {
      expect(await cache.load(signature()), isNull);
    });

    test('שמירה חוזרת על אותה חתימה דורסת', () async {
      final key = signature();

      await cache.save(key, bookOf());
      await cache.save(
        key,
        PaginatedBook(
          pages: [bookOf().pages.first],
          geometry: geometry,
          sectionCount: 3,
        ),
      );

      expect((await cache.load(key))!.pageCount, 1);
    });
  });

  group('פסילת עימוד ישן', () {
    test('שינוי גודל גופן אינו מוצא את הרשומה הקודמת', () async {
      await cache.save(signature(), bookOf());

      final other = signature(
        settings: const RenderSettings(fontSize: 24),
      );

      expect(await cache.load(other), isNull);
    });

    test('שינוי גאומטריה אינו מוצא את הרשומה הקודמת', () async {
      await cache.save(signature(), bookOf());

      expect(
        await cache.load(signature(pageGeometry: geometry.singleColumn)),
        isNull,
      );
    });

    test('שינוי תוכן אינו מוצא את הרשומה הקודמת', () async {
      await cache.save(signature(), bookOf());

      expect(
        await cache.load(signature(lines: const [...content, 'סעיף רביעי'])),
        isNull,
      );
    });

    test('מצב חיפוש אינו פוסל את הרשומה', () async {
      final key = signature();
      await cache.save(key, bookOf());

      final searching = signature(
        settings: const RenderSettings(searchText: 'סעיף'),
      );

      expect(await cache.load(searching), isNotNull);
    });

    test('רשומה שמספר הסעיפים בה אינו תואם לחתימה נפסלת', () async {
      final key = signature();

      // עימוד שנשמר ל-3 סעיפים, אך הרשומה טוענת ל-5.
      await cache.save(key, bookOf(sectionCount: 5));

      expect(await cache.load(key), isNull);
    });
  });

  group('מחיקה', () {
    test('ניקוי לפי זמן גישה מוחק רשומות ישנות בלבד', () async {
      final key = signature();
      await cache.save(key, bookOf());

      await repository.prunePagedLayoutCacheAccessedBefore(
        DateTime.now().millisecondsSinceEpoch - 1000,
      );
      expect(await cache.load(key), isNotNull);

      await repository.prunePagedLayoutCacheAccessedBefore(
        DateTime.now().millisecondsSinceEpoch + 1000,
      );
      expect(await cache.load(key), isNull);
    });
  });

  test('מטמון שאינו נגיש אינו מפיל את הקורא', () async {
    final broken = PagedLayoutCache(
      repositoryProvider: () async => throw StateError('DB נעול'),
    );

    expect(await broken.load(signature()), isNull);
    // שמירה נכשלת בשקט — הקורא כבר קיבל את העימוד שחושב.
    await broken.save(signature(), bookOf());
  });
}
