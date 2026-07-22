import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tools/dictionary/widgets/laaz_hover_region.dart';

/// כל השורות כאן הן מחרוזות אמיתיות מספר "אוצר לעזי רש"י" שבמסד הרשמי.
const String lineMase =
    '3960 / (יואל ד,יא) / <b>עשת</b> מש"א / mase / <b>גוש, עשת</b> <small></small>';
const String lineMac =
    '619 / (פסחים לה.) / <b>כלניתא</b> מ"ק / mac / <b>פרג</b> '
    '<span dir="ltr">✭ poppy</span>';
const String lineMor =
    '3664 / (ירמיה יג,כג) / <b>כושי</b> מו"ר / mor / <b>שחור עור</b> '
    '<small>חסר בכתבי-היד.</small>';
const String lineDeLestencele =
    '3737 / (יחזקאל א,יד) / <b>הבזק</b> די"ל אישטינציל"א / de lestencele / '
    '<b>של הניצוץ</b>';
const String lineSelJeme =
    '1833 / (עבודה זרה כח:) / <b>מלחא גללניתא</b> שי"ל יימ"א / '
    'sel jeme [sel geme] / <b>מלח הסלע</b>';
const String lineRed =
    '24 / (ברכות כח:) / <b>אסדא</b> רי"ד / red [radeau] / <b>רפסודה</b>';
const String lineBis =
    '1594 / (בבא בתרא ד.) / <b>ירוק</b> בי"ש / bis / <b>(שיש) אפור-חום</b>';
const String linePorels =
    '7 / (ברכות ט:) / <b>כרתי</b> פוריל"ש / porels / <b>כרשים (ירק מאכל)</b>';
const String lineFiltres =
    '2065 / (חולין נא.) / <b>מסננת</b> פילטרי"ש / filtres / <b>מסננות</b>';
const String lineBonMalant =
    '5 / (ברכות ח.) / <b>אסכרא</b> בו"ן מלנ"ט / bon malant / '
    '<b>פצע חמור</b>';

/// ראשי תיבות אמיתיים מ-assets/Acronyms.json המתנגשים בתעתיקי הלעז.
const Map<String, List<String>> collidingAcronyms = <String, List<String>>{
  'מש"א': <String>['מה שאמר'],
  'מ"ק': <String>['מועד קטן'],
  'מו"ר': <String>['מורי ורבי'],
  'די"ל': <String>['דיש לומר'],
  'שי"ל': <String>['שיש לומר'],
  'רי"ד': <String>['רבינו ישעיה דטראני'],
  'בי"ש': <String>['בית שמואל'],
};

DictionaryLookupRepository buildRepository(
  List<String> lines, {
  Map<String, List<String>> acronyms = const <String, List<String>>{},
  List<AramaicDictionaryEntry> aramaic = const <AramaicDictionaryEntry>[],
}) {
  return DictionaryLookupRepository(
    loadAcronyms: () async => acronyms,
    loadAramaicEntries: () async => aramaic,
    loadLaazEntries: () async => LaazDictionaryEntry.parseLines(lines),
  );
}

Future<DictionaryLookupRepository> buildLoaded(
  List<String> lines, {
  Map<String, List<String>> acronyms = const <String, List<String>>{},
  List<AramaicDictionaryEntry> aramaic = const <AramaicDictionaryEntry>[],
}) async {
  final repository = buildRepository(
    lines,
    acronyms: acronyms,
    aramaic: aramaic,
  );
  await repository.ensureLoaded();
  return repository;
}

void main() {
  group('דיכוי ריחוף על מילים שהן גם ראשי תיבות', () {
    late DictionaryLookupRepository repository;

    setUp(() async {
      repository = await buildLoaded(
        const <String>[
          lineMase,
          lineMac,
          lineMor,
          lineDeLestencele,
          lineSelJeme,
          lineRed,
          lineBis,
          linePorels,
          lineFiltres,
        ],
        acronyms: collidingAcronyms,
      );
    });

    test('מש"א, מ"ק, מו"ר, די"ל, שי"ל - אין ריחוף לעז', () {
      for (final word in const <String>[
        'מש"א',
        'מ"ק',
        'מו"ר',
        'די"ל',
        'שי"ל',
      ]) {
        expect(
          repository.isLaazHoverSuppressed(word),
          isTrue,
          reason: '$word הוא ראשי תיבות - חייב להיות מדוכא',
        );
        expect(
          laazHoverGroupsFor(word, repository),
          isEmpty,
          reason: '$word אינו אמור להציג חלונית ריחוף',
        );
      }
    });

    test('הלומד לא יקבל "שחור עור" על מו"ר - המקרה המדווח', () {
      // מו"ר = "מורי ורבי"; הלעז mor הוא תקלה גם אם היא נדירה.
      expect(repository.findLaazMatches('מו"ר').single.meaning, 'שחור עור');
      expect(laazHoverGroupsFor('מו"ר', repository), isEmpty);
    });

    test('גם התנגשויות נדירות מדוכאות - אין רף שכיחות', () {
      // רי"ד ובי"ש שכיחים פחות ממש"א, ובכל זאת מדוכאים בדיוק כמותם.
      for (final word in const <String>['רי"ד', 'בי"ש']) {
        expect(repository.isLaazHoverSuppressed(word), isTrue);
        expect(laazHoverGroupsFor(word, repository), isEmpty);
      }
    });

    test('דיכוי חל על כל מפתח מתנגש, בלי רשימה ידנית', () {
      // כל ראש תיבות שהוזרק מתנגש - ולכן כולם מדוכאים.
      for (final acronym in collidingAcronyms.keys) {
        expect(
          repository.isLaazHoverSuppressed(acronym),
          isTrue,
          reason: '$acronym חייב להיכלל בסט הדיכוי',
        );
      }
    });
  });

  group('תפריט ההקשר אינו מושפע - האסימטריה שהתיקון חייב לשמר', () {
    late DictionaryLookupRepository repository;

    setUp(() async {
      repository = await buildLoaded(
        const <String>[
          lineMase,
          lineMac,
          lineMor,
          lineDeLestencele,
          lineSelJeme,
        ],
        acronyms: collidingAcronyms,
      );
    });

    test('אותן מילים עדיין מחזירות התאמות לעז ל-findLaazMatchGroups', () {
      for (final word in const <String>[
        'מש"א',
        'מ"ק',
        'מו"ר',
        'די"ל',
        'שי"ל',
      ]) {
        expect(
          repository.findLaazMatchGroups(word),
          isNotEmpty,
          reason: '$word חייב להישאר זמין בתפריט ההקשר',
        );
        expect(repository.isLikelyLaazTranslit(word), isTrue);
      }
    });

    test('שני הענפים זמינים במקביל: גם לעז וגם ראשי תיבות', () {
      expect(repository.findLaazMatchGroups('מו"ר'), hasLength(1));
      expect(
        repository.findAcronymMatches('מו"ר').single.meanings,
        contains('מורי ורבי'),
      );
    });

    test('הדיכוי לא הוסר מהאינדקס - findLaazMatches שלם', () {
      expect(repository.findLaazMatches('מש"א').single.meaning, 'גוש, עשת');
      expect(repository.findLaazMatches('מ"ק').single.meaning, 'פרג');
    });
  });

  group('לעזים שאינם מתנגשים ממשיכים לרחף כרגיל', () {
    late DictionaryLookupRepository repository;

    setUp(() async {
      repository = await buildLoaded(
        const <String>[
          linePorels,
          lineFiltres,
          lineBonMalant,
          lineMor,
        ],
        acronyms: collidingAcronyms,
      );
    });

    test('פוריל"ש ופילטרי"ש מציגים חלונית', () {
      expect(repository.isLaazHoverSuppressed('פוריל"ש'), isFalse);
      expect(laazHoverGroupsFor('פוריל"ש', repository), hasLength(1));
      expect(
        laazHoverGroupsFor('פוריל"ש', repository).single.single.meaning,
        'כרשים (ירק מאכל)',
      );
      expect(laazHoverGroupsFor('פילטרי"ש', repository), hasLength(1));
    });

    test('מילת תעתיק מתוך ערך רב-מילי שאינה מתנגשת מרחפת', () {
      // "מלנ"ט" מתוך בו"ן מלנ"ט אינה ראשי תיבות ולכן אינה מדוכאת.
      expect(repository.isLaazHoverSuppressed('מלנ"ט'), isFalse);
      expect(laazHoverGroupsFor('מלנ"ט', repository), hasLength(1));
      expect(laazHoverGroupsFor('בו"ן', repository), hasLength(1));
    });
  });

  group('התנגשות מול המילון הארמי', () {
    test('מילה שהיא ערך ארמי מדוכאת אף שאינה ראשי תיבות', () async {
      final repository = await buildLoaded(
        const <String>[lineBis, linePorels],
        aramaic: const <AramaicDictionaryEntry>[
          AramaicDictionaryEntry(aramaic: 'ביש', hebrew: 'רע'),
        ],
      );

      expect(repository.isLaazHoverSuppressed('בי"ש'), isTrue);
      expect(laazHoverGroupsFor('בי"ש', repository), isEmpty);
      // ולעז שאינו במילון הארמי אינו נפגע.
      expect(laazHoverGroupsFor('פוריל"ש', repository), hasLength(1));
    });
  });

  group('מילונים לא נטענו - דיכוי מלא עד שאפשר לאמת', () {
    test('לעז טעון אך ראשי תיבות לא - אין ריחוף על מילה מתנגשת', () async {
      final repository = buildRepository(
        const <String>[lineMor, linePorels],
        acronyms: collidingAcronyms,
      );
      await repository.ensureLaazLoaded();

      expect(repository.areLaazLoaded, isTrue);
      expect(repository.areAcronymsLoaded, isFalse);
      // בלי ראשי תיבות אין דרך לאמת - מדכאים הכל, כולל לעז תקין.
      expect(repository.isLaazHoverSuppressed('מו"ר'), isTrue);
      expect(laazHoverGroupsFor('מו"ר', repository), isEmpty);
      expect(laazHoverGroupsFor('פוריל"ש', repository), isEmpty);
    });

    test('ראשי תיבות טעונים אך ארמית לא - עדיין מדכאים', () async {
      final repository = buildRepository(
        const <String>[lineMor, linePorels],
        acronyms: collidingAcronyms,
      );
      await repository.ensureLaazLoaded();
      await repository.ensureAcronymsLoaded();

      expect(repository.areAramaicLoaded, isFalse);
      expect(repository.isLaazHoverSuppressed('פוריל"ש'), isTrue);
      expect(laazHoverGroupsFor('פוריל"ש', repository), isEmpty);
    });

    test('משנטענו כל המילונים הריחוף חוזר לפעול על לעז תקין', () async {
      final repository = buildRepository(
        const <String>[lineMor, linePorels],
        acronyms: collidingAcronyms,
      );
      await repository.ensureLoaded();

      expect(laazHoverGroupsFor('פוריל"ש', repository), hasLength(1));
      expect(laazHoverGroupsFor('מו"ר', repository), isEmpty);
    });

    test('סדר טעינה הפוך: ראשי תיבות לפני לעז - הדיכוי עדיין נכון', () async {
      final repository = buildRepository(
        const <String>[lineMor, linePorels],
        acronyms: collidingAcronyms,
      );
      await repository.ensureAcronymsLoaded();
      await repository.ensureAramaicLoaded();
      await repository.ensureLaazLoaded();

      expect(repository.isLaazHoverSuppressed('מו"ר'), isTrue);
      expect(repository.isLaazHoverSuppressed('פוריל"ש'), isFalse);
      expect(laazHoverGroupsFor('פוריל"ש', repository), hasLength(1));
    });

    test('כשל בטעינת ראשי תיבות מדכא ריחוף ואינו משאיר סט חלקי', () async {
      final repository = DictionaryLookupRepository(
        loadAcronyms: () async => throw StateError('טעינה נכשלה'),
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[],
        loadLaazEntries: () async =>
            LaazDictionaryEntry.parseLines(const <String>[linePorels]),
      );

      await repository.ensureLoaded();

      expect(repository.areLaazLoaded, isTrue);
      expect(repository.areAcronymsLoaded, isFalse);
      expect(laazHoverGroupsFor('פוריל"ש', repository), isEmpty);
    });
  });
}
