import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';

/// טסטים לבידוד כשלים בין המילונים: כשל בטעינת מילון אחד (למשל לעזי רש"י,
/// שנטען מ-DB ולכן עלול לזרוק) אסור לו להפיל את המילונים מבוססי-האסטים.
void main() {
  const aramaicEntries = <AramaicDictionaryEntry>[
    AramaicDictionaryEntry(aramaic: 'אבא', hebrew: 'יער'),
    AramaicDictionaryEntry(aramaic: 'אבוה', hebrew: 'אביו'),
  ];

  final acronyms = <String, List<String>>{
    'רש"י': <String>['רבי שלמה יצחקי'],
  };

  final laazLines = <String>[
    '7 / (ברכות ט:) / <b>כרתי</b> פוריל"ש / porels / <b>כרשים (ירק מאכל)</b>',
  ];

  DictionaryLookupRepository buildRepository({
    Future<Map<String, List<String>>> Function()? loadAcronyms,
    Future<List<AramaicDictionaryEntry>> Function()? loadAramaicEntries,
    Future<List<LaazDictionaryEntry>> Function()? loadLaazEntries,
  }) {
    return DictionaryLookupRepository(
      loadAcronyms: loadAcronyms ?? () async => acronyms,
      loadAramaicEntries: loadAramaicEntries ?? () async => aramaicEntries,
      loadLaazEntries:
          loadLaazEntries ??
          () async => LaazDictionaryEntry.parseLines(laazLines),
    );
  }

  group('ensureLoaded — בידוד כשל בין המילונים', () {
    test('כשל בטעינת לעזים אינו מונע טעינת ארמי וראשי תיבות', () async {
      final repository = buildRepository(
        loadLaazEntries: () async => throw StateError('DB נעול'),
      );

      await repository.ensureLoaded();

      expect(repository.areLaazLoaded, isFalse);
      expect(repository.areAramaicLoaded, isTrue);
      expect(repository.areAcronymsLoaded, isTrue);
      expect(
        repository.findAcronym('רש״י')?.meanings,
        contains('רבי שלמה יצחקי'),
      );
      expect(repository.findAramaicMatches('אבא'), hasLength(1));
      expect(repository.findLaazMatches('פוריל"ש'), isEmpty);
    });

    test('כשל בטעינת הארמי אינו מונע טעינת לעזים וראשי תיבות', () async {
      final repository = buildRepository(
        loadAramaicEntries: () async => throw StateError('אסט חסר'),
      );

      await repository.ensureLoaded();

      expect(repository.areAramaicLoaded, isFalse);
      expect(repository.areLaazLoaded, isTrue);
      expect(repository.areAcronymsLoaded, isTrue);
      expect(repository.findAramaicMatches('אבא'), isEmpty);
      expect(repository.findLaazMatches('פוריל"ש').single.laazLatin, 'porels');
    });

    test('כשל בטעינת ראשי תיבות אינו מונע טעינת ארמי ולעזים', () async {
      final repository = buildRepository(
        loadAcronyms: () async => throw StateError('JSON פגום'),
      );

      await repository.ensureLoaded();

      expect(repository.areAcronymsLoaded, isFalse);
      expect(repository.areAramaicLoaded, isTrue);
      expect(repository.areLaazLoaded, isTrue);
      expect(repository.findAcronym('רש״י'), isNull);
      expect(repository.findAramaicMatches('אבא'), hasLength(1));
    });

    test('כשל בשני מילונים במקביל משאיר את השלישי טעון', () async {
      final repository = buildRepository(
        loadAcronyms: () async => throw StateError('JSON פגום'),
        loadLaazEntries: () async => throw StateError('DB נעול'),
      );

      await repository.ensureLoaded();

      expect(repository.areAcronymsLoaded, isFalse);
      expect(repository.areLaazLoaded, isFalse);
      expect(repository.areAramaicLoaded, isTrue);
      expect(repository.findAramaicMatches('אבוה'), hasLength(1));
    });

    test('כשל בכל שלושת המילונים אינו זורק מ-ensureLoaded', () async {
      final repository = buildRepository(
        loadAcronyms: () async => throw StateError('א'),
        loadAramaicEntries: () async => throw StateError('ב'),
        loadLaazEntries: () async => throw StateError('ג'),
      );

      await expectLater(repository.ensureLoaded(), completes);
      expect(repository.isLoaded, isFalse);
    });

    test('ensureLoaded מסיים בהצלחה מלאה כשאין כשלים', () async {
      final repository = buildRepository();

      await repository.ensureLoaded();

      expect(repository.isLoaded, isTrue);
      expect(repository.areAcronymsLoaded, isTrue);
      expect(repository.areAramaicLoaded, isTrue);
      expect(repository.areLaazLoaded, isTrue);
    });
  });

  group('ensureLaazLoaded — השגיאה עדיין מגיעה לקורא הישיר', () {
    test('קורא ישיר של ensureLaazLoaded מקבל את השגיאה', () async {
      final repository = buildRepository(
        loadLaazEntries: () async => throw StateError('DB נעול'),
      );

      await expectLater(
        repository.ensureLaazLoaded(),
        throwsA(isA<StateError>()),
      );
      expect(repository.areLaazLoaded, isFalse);
    });

    test('גם אחרי ensureLoaded שבלע את השגיאה, קריאה ישירה זורקת', () async {
      final repository = buildRepository(
        loadLaazEntries: () async => throw StateError('DB נעול'),
      );

      await repository.ensureLoaded();

      await expectLater(
        repository.ensureLaazLoaded(),
        throwsA(isA<StateError>()),
      );
    });

    test('קורא ישיר של ensureAramaicLoaded מקבל את השגיאה', () async {
      final repository = buildRepository(
        loadAramaicEntries: () async => throw StateError('אסט חסר'),
      );

      await expectLater(
        repository.ensureAramaicLoaded(),
        throwsA(isA<StateError>()),
      );
    });

    test('קורא ישיר של ensureAcronymsLoaded מקבל את השגיאה', () async {
      final repository = buildRepository(
        loadAcronyms: () async => throw StateError('JSON פגום'),
      );

      await expectLater(
        repository.ensureAcronymsLoaded(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('התאוששות וניסיון חוזר אחרי כשל', () {
    test('ensureLoaded חוזר מנסה שוב את המילון שנכשל ומצליח', () async {
      var laazAttempts = 0;
      final repository = buildRepository(
        loadLaazEntries: () async {
          laazAttempts++;
          if (laazAttempts == 1) throw StateError('DB נעול זמנית');
          return LaazDictionaryEntry.parseLines(laazLines);
        },
      );

      await repository.ensureLoaded();
      expect(repository.areLaazLoaded, isFalse);

      await repository.ensureLoaded();

      expect(laazAttempts, 2, reason: 'המילון שנכשל נוסה שוב');
      expect(repository.areLaazLoaded, isTrue);
      expect(repository.findLaazMatches('פוריל"ש'), hasLength(1));
    });

    test('מילון שכבר נטען בהצלחה אינו נטען שוב בקריאה חוזרת', () async {
      var aramaicLoads = 0;
      var laazAttempts = 0;
      final repository = buildRepository(
        loadAramaicEntries: () async {
          aramaicLoads++;
          return aramaicEntries;
        },
        loadLaazEntries: () async {
          laazAttempts++;
          throw StateError('DB נעול');
        },
      );

      await repository.ensureLoaded();
      await repository.ensureLoaded();

      expect(aramaicLoads, 1, reason: 'מילון שהצליח נטען פעם אחת בלבד');
      expect(laazAttempts, 2, reason: 'רק המילון שנכשל נוסה מחדש');
    });
  });

  group('מטמון אחרי כשל מול אחרי הצלחה', () {
    test('כשל מנקה את מטמון הלעזים ולא משאיר נתונים חלקיים', () async {
      final loaded = buildRepository();
      await loaded.ensureLoaded();
      expect(loaded.getAllLaazEntries(), hasLength(1));

      final failing = buildRepository(
        loadLaazEntries: () async => throw StateError('DB נעול'),
      );
      await failing.ensureLoaded();

      expect(failing.getAllLaazEntries(), isEmpty);
      expect(failing.findLaazMatches('פוריל"ש'), isEmpty);
    });

    test('כשל בארמי משאיר את מטמון הארמי ריק אך את הלעזים מלא', () async {
      final repository = buildRepository(
        loadAramaicEntries: () async => throw StateError('אסט חסר'),
      );

      await repository.ensureLoaded();

      expect(repository.getAllAramaicEntries(), isEmpty);
      expect(repository.getAllLaazEntries(), hasLength(1));
      expect(repository.getAllAcronyms(), isNotEmpty);
    });
  });

  group('ספר חסר — נטען-ריק ולא כשל', () {
    test('רשימת לעזים ריקה נחשבת טעינה מוצלחת', () async {
      final repository = buildRepository(
        loadLaazEntries: () async => const <LaazDictionaryEntry>[],
      );

      await repository.ensureLoaded();

      expect(
        repository.areLaazLoaded,
        isTrue,
        reason: 'ספר חסר ב-DB מחזיר רשימה ריקה — זו אינה שגיאה',
      );
      expect(repository.isLoaded, isTrue);
      expect(repository.getAllLaazEntries(), isEmpty);
      expect(repository.findLaazMatches('פוריל"ש'), isEmpty);
    });

    test('ensureLaazLoaded ישיר עם ספר חסר אינו זורק', () async {
      final repository = buildRepository(
        loadLaazEntries: () async => const <LaazDictionaryEntry>[],
      );

      await expectLater(repository.ensureLaazLoaded(), completes);
      expect(repository.areLaazLoaded, isTrue);
    });
  });
}
