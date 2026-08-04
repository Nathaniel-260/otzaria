// טסטים לתזמון העימוד המדורג.
//
// המטמון כאן הוא מטמון בזיכרון שמחליף את זה שב-cache.db, וההמתנה לפריים
// מוחלפת ב-microtask — כך הטסטים בודקים את התזמון עצמו ולא את שכבת ה-DB.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/text_book/paged/bloc/paged_layout_cubit.dart';
import 'package:otzaria/text_book/paged/bloc/paged_layout_state.dart';
import 'package:otzaria/text_book/paged/models/page_geometry.dart';
import 'package:otzaria/text_book/paged/models/paged_layout_signature.dart';
import 'package:otzaria/text_book/paged/models/paginated_book.dart';
import 'package:otzaria/text_book/paged/repository/paged_layout_cache.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const geometry = PageGeometry(
    width: 240,
    height: 120,
    margins: EdgeInsets.all(10),
    columns: 2,
    columnGap: 20,
    footerHeight: 0,
    sectionGap: 0,
  );
  const style = TextStyle(fontSize: 10, height: 1);

  /// טקסט שתופס [lines] שורות ברוחב טור 100.
  String section(int lines) => List.filled(lines * 2, 'wwww').join(' ');

  PagedLayoutRequest requestFor(
    List<String> content, {
    String bookId = 'ספר בדיקה',
    bool complete = true,
    RenderSettings settings = const RenderSettings(),
    PageGeometry pageGeometry = geometry,
  }) => PagedLayoutRequest(
    bookId: bookId,
    content: content,
    contentIsComplete: complete,
    geometry: pageGeometry,
    settings: settings,
    textScaler: TextScaler.noScaling,
    locale: const Locale('he', 'IL'),
    buildSpan: (index) => TextSpan(text: content[index], style: style),
    isHeading: (_) => false,
  );

  PagedLayoutCubit cubitWith({
    PagedLayoutCache? cache,
    Duration sliceBudget = const Duration(hours: 1),
    Future<void> Function()? yieldToFrame,
  }) {
    final cubit = PagedLayoutCubit(
      cache: cache ?? _NullCache(),
      sliceBudget: sliceBudget,
      yieldToFrame: yieldToFrame ?? () => Future.microtask(() {}),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  group('תוכן חלקי', () {
    test('אינו מעומד, והמצב מסמן המתנה לתוכן', () async {
      final cubit = cubitWith();

      await cubit.request(requestFor([section(2)], complete: false));

      expect(cubit.state, isA<PagedLayoutWaitingForContent>());
      expect(cubit.signature, isNull);
    });

    test('תוכן שהושלם מעומד בבקשה הבאה', () async {
      final cubit = cubitWith();
      final content = [section(2)];

      await cubit.request(requestFor(content, complete: false));
      await cubit.request(requestFor(content));

      expect(cubit.state, isA<PagedLayoutReady>());
    });
  });

  group('עימוד מלא', () {
    test('ספר קטן מגיע ל-Ready בלי לעבור בפס התקדמות', () async {
      final cubit = cubitWith();
      final seen = <PagedLayoutState>[];
      cubit.stream.listen(seen.add);

      await cubit.request(requestFor([section(2), section(3)]));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state, isA<PagedLayoutReady>());
      expect((cubit.state as PagedLayoutReady).fromCache, isFalse);
      // Running(0) יחיד — הודעת "מתחילים", בלי שלבי התקדמות באמצע.
      expect(seen.whereType<PagedLayoutRunning>(), hasLength(1));
    });

    test('העמודים תואמים לתוכן', () async {
      final cubit = cubitWith();

      await cubit.request(
        requestFor(List.generate(6, (_) => section(10))),
      );

      final book = (cubit.state as PagedLayoutReady).book;
      expect(book.sectionCount, 6);
      expect(book.pageCount, 3);
    });

    test('בקשה חוזרת זהה אינה מעמדת מחדש', () async {
      final cubit = cubitWith();
      final content = [section(4)];

      await cubit.request(requestFor(content));
      final first = (cubit.state as PagedLayoutReady).book;

      await cubit.request(requestFor(content));

      expect((cubit.state as PagedLayoutReady).book, same(first));
    });

    test('שינוי גאומטריה מעמד מחדש', () async {
      final cubit = cubitWith();
      final content = [section(4)];

      await cubit.request(requestFor(content));
      final first = (cubit.state as PagedLayoutReady).book;

      await cubit.request(
        requestFor(content, pageGeometry: geometry.singleColumn),
      );

      expect((cubit.state as PagedLayoutReady).book, isNot(same(first)));
      expect(cubit.signature!.geometry.columns, 1);
    });
  });

  group('התקדמות מדורגת', () {
    test('תקציב זעיר מייצר שלבי התקדמות עולים', () async {
      var yields = 0;
      final cubit = cubitWith(
        sliceBudget: Duration.zero,
        yieldToFrame: () {
          yields++;
          return Future.microtask(() {});
        },
      );
      final progress = <double>[];
      cubit.stream
          .where((state) => state is PagedLayoutRunning)
          .cast<PagedLayoutRunning>()
          .listen((state) => progress.add(state.progress));

      await cubit.request(requestFor(List.generate(8, (_) => section(3))));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state, isA<PagedLayoutReady>());
      expect(yields, greaterThan(1));
      expect(progress.length, greaterThan(2));
      expect(progress, orderedEquals(progress.toList()..sort()));
      expect(progress.last, lessThan(1.0));
    });

    test('בקשה זהה באמצע ריצה אינה מאתחלת את העימוד', () async {
      // התצוגה מבקשת עימוד בכל build, וכל state של ה-bloc מרנדר מחדש. בקשה
      // זהה שלא נבלמת הייתה מתחילה את הספר מאפס בכל הודעה שמגיעה תוך כדי.
      var builds = 0;
      final content = List.generate(30, (_) => section(3));
      // שער ידני במקום המתנה לפריים: כך הבקשה השנייה מגיעה בוודאות בזמן
      // שהעימוד עוד רץ, ולא אחרי שתור ה-microtasks כבר רוקן אותו.
      final gate = <Completer<void>>[];
      final cubit = cubitWith(
        sliceBudget: Duration.zero,
        yieldToFrame: () {
          final completer = Completer<void>();
          gate.add(completer);
          return completer.future;
        },
      );
      PagedLayoutRequest counted() => PagedLayoutRequest(
        bookId: 'ספר בדיקה',
        content: content,
        contentIsComplete: true,
        geometry: geometry,
        settings: const RenderSettings(),
        textScaler: TextScaler.noScaling,
        locale: const Locale('he', 'IL'),
        buildSpan: (index) {
          builds++;
          return TextSpan(text: content[index], style: style);
        },
        isHeading: (_) => false,
      );
      final progress = <double>[];
      cubit.stream
          .where((state) => state is PagedLayoutRunning)
          .cast<PagedLayoutRunning>()
          .listen((state) => progress.add(state.progress));

      final first = cubit.request(counted());
      await Future<void>.delayed(Duration.zero);
      expect(gate, hasLength(1), reason: 'העימוד אמור להיות עצור על השער');
      expect(builds, lessThan(content.length));

      // לא await: בלי הבלימה הבקשה השנייה מתחילה עימוד משלה ונעצרת על השער,
      // וההמתנה לה כאן הייתה תוקעת את הטסט במקום להכשיל אותו.
      final second = cubit.request(counted());

      while (gate.isNotEmpty) {
        gate.removeAt(0).complete();
        await Future<void>.delayed(Duration.zero);
      }
      await Future.wait([first, second]);

      // כל סעיף נבנה פעם אחת בלבד — לא היה אתחול מחדש.
      expect(builds, content.length);
      // ו-Running(0) נשדר פעם אחת, לא שוב בכל בקשה.
      expect(progress.where((value) => value == 0), hasLength(1));
      expect(cubit.state, isA<PagedLayoutReady>());
    });

    test('בקשה חדשה באמצע ריצה נוטשת את הקודמת', () async {
      final cubit = cubitWith(sliceBudget: Duration.zero);
      final long = List.generate(40, (_) => section(4));

      final first = cubit.request(requestFor(long));
      final second = cubit.request(requestFor(long, bookId: 'ספר אחר'));
      await Future.wait([first, second]);

      expect(cubit.state, isA<PagedLayoutReady>());
      expect(cubit.signature!.bookId, 'ספר אחר');
    });

    test('סגירת הקוביט באמצע ריצה אינה זורקת', () async {
      final cubit = PagedLayoutCubit(
        cache: _NullCache(),
        sliceBudget: Duration.zero,
        yieldToFrame: () => Future.microtask(() {}),
      );

      final running = cubit.request(
        requestFor(List.generate(40, (_) => section(4))),
      );
      await Future<void>.delayed(Duration.zero);
      await cubit.close();

      await expectLater(running, completes);
    });
  });

  group('מטמון', () {
    test('עימוד שחושב נשמר, והבקשה הבאה נטענת ממנו', () async {
      final cache = _MemoryCache();
      final content = [section(6), section(6)];

      final first = cubitWith(cache: cache);
      await first.request(requestFor(content));
      await Future<void>.delayed(Duration.zero);
      expect((first.state as PagedLayoutReady).fromCache, isFalse);
      expect(cache.saves, 1);

      final second = cubitWith(cache: cache);
      await second.request(requestFor(content));

      final ready = second.state as PagedLayoutReady;
      expect(ready.fromCache, isTrue);
      expect(
        ready.book.pageCount,
        (first.state as PagedLayoutReady).book.pageCount,
      );
    });

    test('מטמון בגודל אחר אינו נמצא', () async {
      final cache = _MemoryCache();
      final content = [section(6)];

      final first = cubitWith(cache: cache);
      await first.request(requestFor(content));
      await Future<void>.delayed(Duration.zero);

      final second = cubitWith(cache: cache);
      await second.request(
        requestFor(content, settings: const RenderSettings(fontSize: 30)),
      );

      expect((second.state as PagedLayoutReady).fromCache, isFalse);
    });
  });

  test('reset מאפס את החתימה ומחזיר ל-Idle', () async {
    final cubit = cubitWith();
    await cubit.request(requestFor([section(2)]));

    cubit.reset();

    expect(cubit.state, isA<PagedLayoutIdle>());
    expect(cubit.signature, isNull);
  });
}

/// מטמון שאינו שומר דבר — לבדיקת נתיב העימוד עצמו.
class _NullCache extends PagedLayoutCache {
  _NullCache() : super(repositoryProvider: _unused);

  static Future<SeforimRepository> _unused() =>
      throw StateError('לא אמור להיקרא');

  @override
  Future<PaginatedBook?> load(PagedLayoutSignature signature) async => null;

  @override
  Future<void> save(
    PagedLayoutSignature signature,
    PaginatedBook book,
  ) async {}

  @override
  Future<void> invalidateBook(String bookTitle) async {}
}

/// מטמון בזיכרון, מפתוח בדיוק כמו האמיתי.
class _MemoryCache extends _NullCache {
  final Map<String, PaginatedBook> _entries = {};
  int saves = 0;

  @override
  Future<PaginatedBook?> load(PagedLayoutSignature signature) async =>
      _entries[signature.cacheKey];

  @override
  Future<void> save(
    PagedLayoutSignature signature,
    PaginatedBook book,
  ) async {
    saves++;
    _entries[signature.cacheKey] = book;
  }
}
