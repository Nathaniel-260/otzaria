import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tools/dictionary/widgets/laaz_entry_view.dart';
import 'package:otzaria/tools/dictionary/widgets/laaz_hover_region.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';

/// כל השורות כאן הן מחרוזות אמיתיות מספר "אוצר לעזי רש"י" (bookId 5813).
const String lineBonMalant =
    '5 / (ברכות ח.) / <b>אסכרא</b> בו"ן מלנ"ט / bon malant / '
    '<b>פצע חמור</b>';
const String lineCalvaSoriz =
    '843 / (ביצה ז.) / <b>עטלף</b> קלב"א שורי"ץ / chalve soriz / <b>עטלף</b>';
const String lineBrosder =
    '97 / (ברכות סג.) / <b>מחטא דתלמיותא</b> ברושדי"ר של גנביי"ש '
    '(de) brosder [ganbais (de) brosder] / ganbeis / '
    '<b>רקמה של מקטורן מרופד</b>';
const String lineGlaca =
    '190 / (שבת נא:) / <b>ברד</b> גלצא / glace / <b>קֵרָח</b>';
const String lineMartel =
    '3648 / (ירמיה י,ד) / <b>מקבות</b> מרטיל / martel / <b>פטיש</b>';
const String lineRosel =
    '3068 / (שמות ב,ג) / <b>סוף</b> רושיל / rosel / <b>סוף</b>';
const String lineMasiz =
    '4278 / (שה"ש ה,יד) / <b>עשת</b> משיץ / masiz / <b>גושי, מקשה</b>';
const String lineChevile =
    '66 / (ברכות נד:) / <b>(קרסוליה) [קרסול]</b> קיביל"א (cheville) / '
    'chevile / <b>קרסול</b>';
const String lineBlez =
    '77 / (ברכות נז:) / <b>תרדין</b> בלי"ץ () blez / bliz / <b>סלק</b>';
const String lineTenailles =
    '388 / (שבת קי.) / <b>צבתא</b> טינליי"ש () [tenailles] / tenalies / '
    '<b>צבת</b>';
const String lineEstornel =
    '1430 / (בבא קמא צב:) / <b>זרזיר</b> אישטורני"ל / estornel / <b>זרזיר</b>';
const String lineLoje =
    '1982 / (מנחות לג:) / <b>אכסדרא רומיתא</b> לוי"א / [loge] loje / '
    '<b>סוכה</b>';
const String lineAnse =
    '64 / (ברכות נב:) / <b>אוזן</b> אנש"א / anse / <b>אוזן, ידית (של כלי)</b>';
const String lineAinse =
    '1331 / (גיטין ע.) / <b>פחד</b> אינש"א / ainse / <b>דאגה</b>';
const String lineEsfreier =
    '2660 / (עבודה זרה כח:) / <b>תיצטנן</b> אישפריי"ר / esfreier / '
    '<b>לטשטש</b>';
const String lineEsproier =
    '2661 / (עבודה זרה כט.) / <b>מנפץ</b> אישפרויי"ר / esproier / '
    '<b>לנפץ</b>';
const String linePorels =
    '7 / (ברכות ט:) / <b>כרתי</b> פוריל"ש / porels / <b>כרשים (ירק מאכל)</b>';

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DictionaryLookupRepository buildRepository(
  List<String> lines, {
  Map<String, List<String>> acronyms = const <String, List<String>>{},
}) {
  return DictionaryLookupRepository(
    loadAcronyms: () async => acronyms,
    loadAramaicEntries: () async => const <AramaicDictionaryEntry>[],
    loadLaazEntries: () async => LaazDictionaryEntry.parseLines(lines),
  );
}

void main() {
  group('BUG A - תעתיק רב-מילי נמצא גם לפי מילה בודדת', () {
    late DictionaryLookupRepository repository;

    setUp(() async {
      repository = buildRepository(const <String>[
        lineBonMalant,
        lineCalvaSoriz,
        lineBrosder,
      ]);
      await repository.ensureLaazLoaded();
    });

    test('המחרוזת המלאה עדיין נמצאת (לא נשברה ההתנהגות הקיימת)', () {
      expect(repository.findLaazMatches('בו"ן מלנ"ט'), hasLength(1));
      expect(
        repository.findLaazMatches('בו"ן מלנ"ט').single.meaning,
        'פצע חמור',
      );
    });

    test('כל אחת ממילות התעתיק מוצאת את הערך - זה הבאג שתוקן', () {
      expect(repository.findLaazMatches('בו"ן'), hasLength(1));
      expect(repository.findLaazMatches('מלנ"ט'), hasLength(1));
      expect(repository.findLaazMatches('בו"ן').single.lemma, 'אסכרא');
      expect(repository.findLaazMatches('מלנ"ט').single.meaning, 'פצע חמור');
    });

    test('תעתיק דו-מילי נוסף: קלב"א שורי"ץ', () {
      expect(repository.findLaazMatches('קלב"א'), hasLength(1));
      expect(repository.findLaazMatches('שורי"ץ'), hasLength(1));
      expect(repository.findLaazMatches('קלב"א').single.meaning, 'עטלף');
    });

    test('תעתיק תלת-מילי: כל מילה נושאת גרשיים מאונדקסת', () {
      expect(repository.findLaazMatches('ברושדי"ר'), isNotEmpty);
      expect(repository.findLaazMatches('גנביי"ש'), isNotEmpty);
      // "של" היא מילת קישור בלי גרשיים - לא מפתח לעז.
      expect(repository.findLaazMatches('של'), isEmpty);
    });

    test('מילות קישור בנות שתי אותיות אינן הופכות למפתח לעז', () async {
      final repo = buildRepository(const <String>[
        '3121 / (שמות טו,ב) / <b>ואנוהו</b> א"י ל"א מייזונ"ט / '
            'e la maisonete / <b>ואת ביתו</b>',
      ]);
      await repo.ensureLaazLoaded();

      // א"י ו-ל"א מתנרמלות ל-2 אותיות; אינדוקס שלהן היה מתנגש
      // בראשי התיבות "ארץ ישראל" ו"לא אמרינן".
      expect(repo.findLaazMatches('א"י'), isEmpty);
      expect(repo.findLaazMatches('ל"א'), isEmpty);
      expect(repo.findLaazMatches('מייזונ"ט'), hasLength(1));
    });

    test('מילה משותפת לשני ערכים מחזירה את שתי הקבוצות', () async {
      final repo = buildRepository(const <String>[
        lineBonMalant,
        '41 / (ברכות מ.) / <b>אסכרה</b> בו"ן מלנ"ט / bon malant / '
            '<b>פצע חמור</b>',
        '900 / (חולין נ.) / <b>בדיקה</b> בו"ן פיש"א / bon pise / '
            '<b>בדיקה טובה</b>',
      ]);
      await repo.ensureLaazLoaded();

      // "בו"ן" משותפת לשני לעזים שונים - שתי קבוצות, המשתמש בוחר.
      expect(repo.findLaazMatchGroups('בו"ן'), hasLength(2));
    });
  });

  group('BUG B - תעתיק ללא גרשיים', () {
    late DictionaryLookupRepository repository;

    setUp(() async {
      repository = buildRepository(const <String>[
        lineGlaca,
        lineMartel,
        lineRosel,
        lineMasiz,
        linePorels,
      ]);
      await repository.ensureLaazLoaded();
    });

    test('isLikelyLaazTranslit מאשר תעתיק ללא גרשיים שקיים באינדקס', () {
      expect(repository.isLikelyLaazTranslit('גלצא'), isTrue);
      expect(repository.isLikelyLaazTranslit('מרטיל'), isTrue);
      expect(repository.isLikelyLaazTranslit('רושיל'), isTrue);
      expect(repository.isLikelyLaazTranslit('משיץ'), isTrue);
    });

    test('שער הריחוף מחזיר קבוצות לתעתיק ללא גרשיים', () {
      expect(laazHoverGroupsFor('גלצא', repository), hasLength(1));
      expect(laazHoverGroupsFor('מרטיל', repository), hasLength(1));
      expect(
        laazHoverGroupsFor('גלצא', repository).single.single.meaning,
        'קֵרָח',
      );
    });

    test('שער התפריט (isLikelyLaazTranslit) פותח ענף לעז', () {
      expect(repository.findLaazMatches('מרטיל').single.meaning, 'פטיש');
      expect(repository.findLaazMatches('רושיל').single.laazLatin, 'rosel');
    });

    test('שלילי: מילים עבריות רגילות שאינן באינדקס אינן לעז', () {
      for (final word in const <String>['צפון', 'אמר', 'בית', 'שלום', 'ברד']) {
        expect(
          repository.isLikelyLaazTranslit(word),
          isFalse,
          reason: '$word אינה תעתיק לעז',
        );
        expect(laazHoverGroupsFor(word, repository), isEmpty);
      }
    });

    test('שלילי: מילת הערך של רש"י אינה מפעילה לעז', () {
      // "ברד" היא ה-lemma של גלצא - רק התעתיק מזוהה, לא מילת הערך.
      expect(repository.findLaazMatches('ברד'), isEmpty);
    });

    test('הבדיקה נשארת זולה: גרשיים מזוהים בלי תלות באינדקס', () {
      final notLoaded = buildRepository(const <String>[lineGlaca]);

      expect(notLoaded.isLikelyLaazTranslit('פוריל"ש'), isTrue);
      // בלי טעינה אין אינדקס, ולכן מילה ללא גרשיים אינה עוברת.
      expect(notLoaded.isLikelyLaazTranslit('גלצא'), isFalse);
    });
  });

  group('BUG C - ניקוי זנב לטיני/סוגריים מהתעתיק', () {
    test('קיביל"א (cheville) מנוקה לתעתיק בלבד', () {
      final entry = LaazDictionaryEntry.parseLine(lineChevile);

      expect(entry, isNotNull);
      expect(entry!.laazHebrew, 'קיביל"א');
      expect(entry.laazLatin, 'chevile');
      expect(entry.meaning, 'קרסול');
    });

    test('בלי"ץ () blez מנוקה - הסוגריים אינם נכנסים למפתח', () {
      final entry = LaazDictionaryEntry.parseLine(lineBlez);

      expect(entry, isNotNull);
      expect(entry!.laazHebrew, 'בלי"ץ');
      expect(entry.meaning, 'סלק');
    });

    test('טינליי"ש () [tenailles] מנוקה', () {
      final entry = LaazDictionaryEntry.parseLine(lineTenailles);

      expect(entry, isNotNull);
      expect(entry!.laazHebrew, 'טינליי"ש');
      expect(entry.laazLatin, 'tenalies');
    });

    test('חיפוש לפי המילה הנקייה מוצא את הערך', () async {
      final repository = buildRepository(const <String>[
        lineChevile,
        lineBlez,
        lineTenailles,
      ]);
      await repository.ensureLaazLoaded();

      expect(repository.findLaazMatches('בלי"ץ'), hasLength(1));
      expect(repository.findLaazMatches('קיביל"א'), hasLength(1));
      expect(repository.findLaazMatches('טינליי"ש'), hasLength(1));
      expect(repository.findLaazMatches('בלי"ץ').single.meaning, 'סלק');
    });

    test('cleanLaazHebrew משאיר תעתיק נקי ללא שינוי', () {
      expect(LaazDictionaryEntry.cleanLaazHebrew('פוריל"ש'), 'פוריל"ש');
      expect(
        LaazDictionaryEntry.cleanLaazHebrew('בו"ן מלנ"ט'),
        'בו"ן מלנ"ט',
      );
    });

    test('cleanLaazHebrew אינו מאבד ערך שכולו לטיני', () {
      // עדיף להשאיר את המקור מאשר להחזיר מחרוזת ריקה.
      expect(LaazDictionaryEntry.cleanLaazHebrew('[]'), isNotEmpty);
    });
  });

  group('וריאנטים של כתיב - איתור לעז שנכתב אחרת ברש"י', () {
    late DictionaryLookupRepository repository;

    setUp(() async {
      repository = buildRepository(const <String>[
        lineEstornel,
        lineLoje,
        lineAnse,
        lineAinse,
        linePorels,
      ]);
      await repository.ensureLaazLoaded();
    });

    test('אשטורוני"ל שברש"י מוצא את אישטורני"ל שבספר - המקרה המדווח', () {
      final matches = repository.findLaazMatches('אשטורוני"ל');

      expect(matches, isNotEmpty);
      expect(matches.first.meaning, 'זרזיר');
      expect(matches.first.laazLatin, 'estornel');
    });

    test('ה\' סופית וא\' סופית הן אותו תעתיק', () {
      expect(repository.findLaazMatches('לוי"ה'), hasLength(1));
      expect(repository.findLaazMatches('לוי"ה').single.meaning, 'סוכה');
    });

    test('התאמה מדויקת תמיד מנצחת ואינה מוחלפת בווריאנט', () {
      // אנש"א ואינש"א שתיהן קיימות - כל אחת חייבת להישאר עם הפירוש שלה.
      expect(
        repository.findLaazMatches('אנש"א').first.meaning,
        contains('אוזן'),
      );
      expect(repository.findLaazMatches('אינש"א').first.meaning, 'דאגה');
    });

    test('שלילי: שני וריאנטים מתאימים מחזירים ריק ולא ניחוש', () async {
      final ambiguous = buildRepository(const <String>[
        lineEsfreier,
        lineEsproier,
      ]);
      await ambiguous.ensureLaazLoaded();

      // אשפריי"ר מתאים גם לאישפריי"ר וגם לאישפרויי"ר - עדיף כלום מפירוש שגוי.
      expect(ambiguous.findLaazMatches('אשפריי"ר'), isEmpty);
    });

    test('מילה שאינה לעז כלל אינה מוצאת דבר דרך וריאנטים', () {
      expect(repository.findLaazMatches('שלום'), isEmpty);
      expect(repository.findLaazMatches('צפון'), isEmpty);
    });
  });

  group('התנגשות לעז/ראשי תיבות - שני הענפים מוצגים', () {
    test('מילה שהיא גם לעז וגם ראשי תיבות מזוהה בשני המילונים', () async {
      // בי"ש: לעז "אפור-חום" מול ראשי תיבות "בית שמואל" - התנגשות אמיתית.
      final repository = buildRepository(
        const <String>[
          '2246 / (חולין מז:) / <b>גוון</b> בי"ש / bis / <b>(שיש)אפור-חום</b>',
        ],
        acronyms: const <String, List<String>>{
          'בי"ש': <String>['בידי שמים', 'בית שמואל'],
        },
      );
      await repository.ensureLaazLoaded();
      await repository.ensureAcronymsLoaded();

      expect(repository.isLikelyLaazTranslit('בי"ש'), isTrue);
      expect(repository.isLikelyAcronym('בי"ש'), isTrue);
      expect(repository.findLaazMatches('בי"ש'), hasLength(1));
      expect(repository.findAcronymMatches('בי"ש'), hasLength(1));
      // אף ענף אינו מבטל את השני.
      expect(
        repository.findAcronymMatches('בי"ש').single.meanings,
        contains('בית שמואל'),
      );
    });
  });

  group('טעינה במקביל ובידוד כשלים', () {
    test('שתי קריאות מקבילות טוענות פעם אחת בלבד', () async {
      var calls = 0;
      final repository = DictionaryLookupRepository(
        loadAcronyms: () async => <String, List<String>>{},
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[],
        loadLaazEntries: () async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return LaazDictionaryEntry.parseLines(const <String>[linePorels]);
        },
      );

      await Future.wait<void>([
        repository.ensureLaazLoaded(),
        repository.ensureLaazLoaded(),
      ]);

      expect(calls, 1);
      expect(repository.areLaazLoaded, isTrue);
    });

    test('כשל בטעינת לעז אינו מונע טעינת ארמית וראשי תיבות', () async {
      final repository = DictionaryLookupRepository(
        loadAcronyms: () async => <String, List<String>>{
          'רש"י': <String>['רבי שלמה יצחקי'],
        },
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[
          AramaicDictionaryEntry(aramaic: 'גברא', hebrew: 'איש'),
        ],
        loadLaazEntries: () async => throw StateError('טעינה נכשלה'),
      );

      await repository.ensureLoaded();

      expect(repository.areAcronymsLoaded, isTrue);
      expect(repository.areAramaicLoaded, isTrue);
      expect(repository.areLaazLoaded, isFalse);
    });
  });

  group('LaazHoverRegion - התנהגות ריחוף', () {
    const text = 'אמר גלצא היום';

    Future<void> pumpRegion(
      WidgetTester tester,
      DictionaryLookupRepository repository,
    ) async {
      await tester.pumpWidget(
        BlocProvider<SettingsBloc>(
          create: (_) => _TestSettingsBloc(),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: LaazHoverRegion(
                  repository: repository,
                  child: const Text(text),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('כותרת החלונית מוצגת בלי זנב לטיני או סוגריים', (
      tester,
    ) async {
      final repository = buildRepository(const <String>[lineChevile]);
      await repository.ensureLaazLoaded();
      final group = repository.findLaazMatchGroups('קיביל"א');

      await tester.pumpWidget(
        BlocProvider<SettingsBloc>(
          create: (_) => _TestSettingsBloc(),
          child: MaterialApp(
            home: Scaffold(body: LaazHoverPreviewContent(groups: group)),
          ),
        ),
      );

      expect(find.textContaining('קיביל', findRichText: true), findsOneWidget);
      expect(
        find.textContaining('cheville', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('(', findRichText: true), findsNothing);
    });

    testWidgets('אין חלונית לפני שחלף זמן ההשהיה, ויש אחריו', (tester) async {
      final repository = buildRepository(const <String>[lineGlaca]);
      await repository.ensureLaazLoaded();
      await pumpRegion(tester, repository);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();

      final paragraph = tester.renderObject<RenderParagraph>(
        find.textContaining('אמר', findRichText: true),
      );
      final caret = paragraph.getOffsetForCaret(
        TextPosition(offset: text.indexOf('גלצא') + 2),
        Rect.zero,
      );
      await gesture.moveTo(
        paragraph.localToGlobal(caret + const Offset(1, 5)),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('קֵרָח', findRichText: true), findsNothing);

      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(find.textContaining('קֵרָח', findRichText: true), findsOneWidget);

      LinkPreviewOverlay.dismiss();
      await tester.pump();
    });

    testWidgets('מגע (לא עכבר) אינו מפעיל חלונית', (tester) async {
      final repository = buildRepository(const <String>[lineGlaca]);
      await repository.ensureLaazLoaded();
      await pumpRegion(tester, repository);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();

      final paragraph = tester.renderObject<RenderParagraph>(
        find.textContaining('אמר', findRichText: true),
      );
      final caret = paragraph.getOffsetForCaret(
        TextPosition(offset: text.indexOf('גלצא') + 2),
        Rect.zero,
      );
      await gesture.moveTo(
        paragraph.localToGlobal(caret + const Offset(1, 5)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.textContaining('קֵרָח', findRichText: true), findsNothing);
    });
  });
}
