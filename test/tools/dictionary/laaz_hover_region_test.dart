import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tools/dictionary/widgets/laaz_hover_region.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';

DictionaryLookupRepository buildRepository({
  List<String> extraLines = const <String>[],
}) {
  return DictionaryLookupRepository(
    loadAcronyms: () async => <String, List<String>>{},
    loadAramaicEntries: () async => const <AramaicDictionaryEntry>[],
    loadLaazEntries: () async => LaazDictionaryEntry.parseLines(<String>[
      '7 / (ברכות ט:) / <b>כרתי</b> פוריל"ש / porels / '
          '<b>כרשים (ירק מאכל)</b> <small>הערת בדיקה</small> '
          '<span dir="ltr">a leek</span>',
      ...extraLines,
    ]),
  );
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('laazHoverGroupsFor', () {
    test('מחזיר ריק למילה ריקה או null', () async {
      final repository = buildRepository();
      await repository.ensureLoaded();

      expect(laazHoverGroupsFor(null, repository), isEmpty);
      expect(laazHoverGroupsFor('', repository), isEmpty);
    });

    test('מחזיר ריק כשהמילון עדיין לא נטען', () {
      final repository = buildRepository();

      expect(laazHoverGroupsFor('פוריל"ש', repository), isEmpty);
    });

    test('מחזיר ריק למילה שאינה תעתיק לעז, גם כשהיא מילת ערך', () async {
      final repository = buildRepository();
      await repository.ensureLoaded();

      expect(laazHoverGroupsFor('כרתי', repository), isEmpty);
      expect(laazHoverGroupsFor('שלום', repository), isEmpty);
    });

    test('מחזיר ריק לתעתיק לעז ללא התאמה במילון', () async {
      final repository = buildRepository();
      await repository.ensureLoaded();

      expect(laazHoverGroupsFor('אב"ג', repository), isEmpty);
    });

    test('מחזיר קבוצות לתעתיק לעז עם התאמה', () async {
      final repository = buildRepository();
      await repository.ensureLoaded();

      final groups = laazHoverGroupsFor('פוריל"ש', repository);

      expect(groups, hasLength(1));
      expect(groups.single.single.meaning, 'כרשים (ירק מאכל)');
    });
  });

  group('LaazHoverRegion', () {
    const text = 'אמר פוריל"ש היום';

    Future<void> pumpRegion(
      WidgetTester tester,
      DictionaryLookupRepository repository, {
      Widget child = const Text(text),
    }) async {
      await tester.pumpWidget(
        BlocProvider<SettingsBloc>(
          create: (_) => _TestSettingsBloc(),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: LaazHoverRegion(repository: repository, child: child),
              ),
            ),
          ),
        ),
      );
    }

    Offset wordCenter(WidgetTester tester, String target) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.textContaining('אמר', findRichText: true),
      );
      final charIndex = text.indexOf(target) + target.length ~/ 2;
      final caret = paragraph.getOffsetForCaret(
        TextPosition(offset: charIndex),
        Rect.zero,
      );
      return paragraph.localToGlobal(caret + const Offset(1, 5));
    }

    Future<TestGesture> startMouse(WidgetTester tester) async {
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      return gesture;
    }

    testWidgets('ריחוף על מילת לעז מציג חלונית עם שם הלעז והפירוש', (
      tester,
    ) async {
      final repository = buildRepository();
      await repository.ensureLoaded();
      await pumpRegion(tester, repository);
      final gesture = await startMouse(tester);

      await gesture.moveTo(wordCenter(tester, 'פוריל"ש'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      // שם הלעז מופיע פעמיים: בטקסט שמתחת ובכותרת החלונית.
      expect(
        find.textContaining('פוריל', findRichText: true),
        findsNWidgets(2),
      );
      expect(
        find.textContaining('כרשים', findRichText: true),
        findsOneWidget,
      );

      LinkPreviewOverlay.dismiss();
      await tester.pump();
    });

    testWidgets('החלונית אינה מציגה לטינית, מקורות, הערות או אנגלית', (
      tester,
    ) async {
      final repository = buildRepository();
      await repository.ensureLoaded();
      await pumpRegion(tester, repository);
      final gesture = await startMouse(tester);

      await gesture.moveTo(wordCenter(tester, 'פוריל"ש'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(
        find.textContaining('כרשים', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('porels', findRichText: true), findsNothing);
      expect(find.textContaining('רש"י', findRichText: true), findsNothing);
      expect(find.textContaining('ברכות', findRichText: true), findsNothing);
      expect(
        find.textContaining('הערת בדיקה', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('leek', findRichText: true), findsNothing);

      LinkPreviewOverlay.dismiss();
      await tester.pump();
    });

    testWidgets('כמה פירושים שונים — כל אחד מוצג כשם ופירוש בלבד', (
      tester,
    ) async {
      final repository = buildRepository(
        extraLines: const <String>[
          '12 / (שבת י.) / <b>חציר</b> פוריל"ש / porels / <b>עשב מאכל</b>',
        ],
      );
      await repository.ensureLoaded();
      await pumpRegion(tester, repository);
      final gesture = await startMouse(tester);

      await gesture.moveTo(wordCenter(tester, 'פוריל"ש'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      // הטקסט שמתחת + שתי כותרות שם-לעז בחלונית.
      expect(
        find.textContaining('פוריל', findRichText: true),
        findsNWidgets(3),
      );
      expect(
        find.textContaining('כרשים', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('עשב מאכל', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('porels', findRichText: true), findsNothing);
      expect(find.textContaining('שבת', findRichText: true), findsNothing);

      LinkPreviewOverlay.dismiss();
      await tester.pump();
    });

    testWidgets('הזזת הסמן למילה רגילה סוגרת את החלונית', (tester) async {
      final repository = buildRepository();
      await repository.ensureLoaded();
      await pumpRegion(tester, repository);
      final gesture = await startMouse(tester);
      // מחשבים את שני המיקומים לפני פתיחת החלונית — אחרי הפתיחה גם כותרת
      // החלונית מכילה את התעתיק והחיפוש בטקסט אינו חד-משמעי.
      final laazCenter = wordCenter(tester, 'פוריל"ש');
      final plainCenter = wordCenter(tester, 'אמר');

      await gesture.moveTo(laazCenter);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(
        find.textContaining('כרשים', findRichText: true),
        findsOneWidget,
      );

      await gesture.moveTo(plainCenter);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('כרשים', findRichText: true), findsNothing);
    });

    testWidgets('ריחוף על מילה ללא התאמה אינו מציג חלונית', (tester) async {
      final repository = buildRepository();
      await repository.ensureLoaded();
      await pumpRegion(tester, repository);
      final gesture = await startMouse(tester);

      await gesture.moveTo(wordCenter(tester, 'היום'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.textContaining('כרשים', findRichText: true), findsNothing);
    });

    testWidgets('מילת לעז בתוך קישור לחיץ אינה מציגה חלונית לעז', (
      tester,
    ) async {
      final repository = buildRepository();
      await repository.ensureLoaded();
      final recognizer = TapGestureRecognizer()..onTap = () {};
      addTearDown(recognizer.dispose);
      await pumpRegion(
        tester,
        repository,
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'אמר '),
              TextSpan(text: 'פוריל"ש', recognizer: recognizer),
              const TextSpan(text: ' היום'),
            ],
          ),
        ),
      );
      final gesture = await startMouse(tester);

      await gesture.moveTo(wordCenter(tester, 'פוריל"ש'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.textContaining('כרשים', findRichText: true), findsNothing);
    });

    testWidgets('אזור מקונן בתוך אזור קיים הופך שקוף', (tester) async {
      final repository = buildRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LaazHoverRegion(
              repository: repository,
              child: LaazHoverRegion(
                repository: repository,
                child: const Text(text),
              ),
            ),
          ),
        ),
      );

      final outer = find.byType(LaazHoverRegion).first;
      final inner = find.byType(LaazHoverRegion).last;
      expect(
        find.descendant(of: inner, matching: find.byType(MouseRegion)),
        findsNothing,
      );
      expect(
        find.descendant(of: outer, matching: find.byType(MouseRegion)),
        findsOneWidget,
      );
    });
  });
}
