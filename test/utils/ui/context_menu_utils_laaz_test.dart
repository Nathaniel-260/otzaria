// שחבור ערכי המילון (ראשי תיבות / ארמית / לעזי רש"י) לתפריט ההקשר של מפרש:
// המפריד נוסף רק כשיש ערכים, והמילה תחת הסמן משמשת כשאין טקסט מסומן.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/utils/ui/context_menu_utils.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import '../../test_helpers/memory_cache_provider.dart';

const String _laazTranslit = 'פוריל"ש';
const String _laazLine =
    '7 / (ברכות ט:) / <b>כרתי</b> $_laazTranslit / porels / <b>כרשים (ירק מאכל)</b>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Link makeLink() => Link(
    heRef: 'רש"י על בראשית א:א',
    index1: 1,
    path2: 'אוצריא/תנך/פירושים/רשי.txt',
    index2: 1,
    connectionType: 'commentary',
  );

  /// repository עם טעינה מוזרקת בלבד — ללא גישה ל-DB האמיתי.
  DictionaryLookupRepository buildRepository({
    List<String> laazLines = const [],
  }) {
    return DictionaryLookupRepository(
      loadAcronyms: () async => <String, List<String>>{},
      loadAramaicEntries: () async => const <AramaicDictionaryEntry>[],
      loadLaazEntries: () async => LaazDictionaryEntry.parseLines(laazLines),
    );
  }

  /// מרנדר עץ עם TourCubit (נדרש בלחיצה על ערך) ובונה את התפריט דרך helper
  /// הייצור *אחרי* ה-layout — כמו בייצור, שבו התפריט נבנה בלחיצה ימנית.
  /// בנייה בזמן ה-build הראשון תיכשל ב-hit-test של המילה תחת הסמן.
  Future<List<AppContextMenuEntry>> pumpMenu(
    WidgetTester tester, {
    String? savedSelectedText,
    Offset Function()? tapPosition,
    DictionaryLookupRepository? repository,
    Widget? body,
  }) async {
    final tourCubit = TourCubit();
    addTearDown(() async => tourCubit.close());
    late BuildContext menuContext;

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<TourCubit>.value(
          value: tourCubit,
          child: Scaffold(
            body: Builder(
              builder: (context) {
                menuContext = context;
                return body ?? const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return ContextMenuUtils.buildCommentaryContextMenu(
      context: menuContext,
      link: makeLink(),
      openBookCallback: (_) {},
      fontSize: 18,
      savedSelectedText: savedSelectedText,
      onCopySelected: () {},
      tapPosition: tapPosition?.call(),
      dictionaryRepository: repository,
    );
  }

  group('שחבור ערכי מילון לתפריט ההקשר של מפרש', () {
    testWidgets('טקסט מסומן שהוא תעתיק לעז - נוסף ערך "לעזי רש"י"', (
      tester,
    ) async {
      final repository = buildRepository(laazLines: const [_laazLine]);
      await repository.ensureLaazLoaded();

      final entries = await pumpMenu(
        tester,
        savedSelectedText: _laazTranslit,
        repository: repository,
      );

      final laaz = entries.where((e) => e.label == 'לעזי רש"י').toList();
      expect(
        laaz,
        hasLength(1),
        reason: 'תעתיק לעז מסומן חייב להוסיף את ערך המילון',
      );
      expect(
        laaz.single.children,
        isNotEmpty,
        reason: 'הערך חייב להכיל את ההתאמות שנמצאו',
      );
    });

    testWidgets('אין התאמה במילון - אין ערכים ואין מפריד מיותר', (
      tester,
    ) async {
      final repository = buildRepository(laazLines: const [_laazLine]);
      await repository.ensureLaazLoaded();

      final entries = await pumpMenu(
        tester,
        savedSelectedText: 'שלום',
        repository: repository,
      );

      expect(entries.any((e) => e.label == 'לעזי רש"י'), isFalse);
      expect(
        entries.last.isDivider,
        isFalse,
        reason: 'מפריד ללא ערכים אחריו הוא מפריד יתום',
      );
      // "דווח על טעות" הוא הפריט האחרון; המפריד שלפניו הוא היחיד שנוסף אחרי
      // פריטי הבסיס. מפריד נוסף מעיד על שחבור מילון ריק.
      expect(
        entries.where((e) => e.isDivider).length,
        2,
        reason: 'מפריד הבסיס + מפריד הדיווח בלבד',
      );
    });

    testWidgets('המילון לא נטען - אין ערכים ואין מפריד', (tester) async {
      final repository = buildRepository(laazLines: const [_laazLine]);

      final entries = await pumpMenu(
        tester,
        savedSelectedText: _laazTranslit,
        repository: repository,
      );

      expect(entries.any((e) => e.label == 'לעזי רש"י'), isFalse);
      expect(entries.where((e) => e.isDivider).length, 2);
    });

    testWidgets(
      'אין טקסט מסומן - הלעז נלקח מהמילה תחת הסמן (wordAtGlobalPosition)',
      (tester) async {
        final repository = buildRepository(laazLines: const [_laazLine]);
        await repository.ensureLaazLoaded();

        // ה-body מרונדר כדי שה-hit-test ימצא RenderParagraph אמיתי.
        const key = ValueKey<String>('laaz-word');
        final entries = await pumpMenu(
          tester,
          savedSelectedText: null,
          tapPosition: () => tester.getCenter(find.byKey(key)),
          repository: repository,
          body: const Center(child: Text(_laazTranslit, key: key)),
        );

        expect(
          entries.any((e) => e.label == 'לעזי רש"י'),
          isTrue,
          reason:
              'בלי טקסט מסומן, המילה תחת הסמן היא מקור החיפוש — אחרת אין לעז '
              'בלחיצה ימנית על מילה',
        );
      },
    );

    testWidgets('טקסט מסומן גובר על המילה תחת הסמן', (tester) async {
      final repository = buildRepository(laazLines: const [_laazLine]);
      await repository.ensureLaazLoaded();

      const key = ValueKey<String>('other-word');

      // בחירה תקפה שאינה לעז: אסור ליפול חזרה למילה תחת הסמן (שכן היא לעז).
      final entries = await pumpMenu(
        tester,
        savedSelectedText: 'שלום',
        tapPosition: () => tester.getCenter(find.byKey(key)),
        repository: repository,
        body: const Center(child: Text(_laazTranslit, key: key)),
      );

      expect(
        entries.any((e) => e.label == 'לעזי רש"י'),
        isFalse,
        reason: 'הבחירה המפורשת גוברת — אין נפילה למילה תחת הסמן',
      );
    });

    testWidgets('ה-repository המוזרק הוא זה שנשאל (ולא ה-singleton)', (
      tester,
    ) async {
      final repository = _SpyRepository();
      await repository.ensureLaazLoaded();

      await pumpMenu(
        tester,
        savedSelectedText: _laazTranslit,
        repository: repository,
      );

      expect(
        repository.wasQueried,
        isTrue,
        reason: 'בלי הזרקה אמיתית הבדיקות כאן היו בודקות את ה-singleton',
      );
    });
  });
}

/// repository שמדווח אם נשאל על התאמות לעז — מאמת את תפר ההזרקה.
class _SpyRepository extends DictionaryLookupRepository {
  _SpyRepository()
    : super(
        loadAcronyms: () async => <String, List<String>>{},
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[],
        loadLaazEntries: () async =>
            LaazDictionaryEntry.parseLines(const [_laazLine]),
      );

  bool wasQueried = false;

  @override
  List<List<LaazDictionaryEntry>> findLaazMatchGroups(String raw) {
    wasQueried = true;
    return super.findLaazMatchGroups(raw);
  }
}
