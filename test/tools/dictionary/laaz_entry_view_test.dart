import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tools/dictionary/widgets/laaz_entry_view.dart';
import 'package:otzaria/widgets/misc/link_context_menu_entry.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
import 'package:otzaria/widgets/misc/link_preview_styles.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';

const _entry = LaazDictionaryEntry(
  entryNumber: '7',
  sourceReference: 'ברכות ט:',
  lemma: 'כרתי',
  laazHebrew: 'פוריל"ש',
  laazLatin: 'porels',
  meaning: 'כרשים (ירק מאכל)',
  note: 'הערת עורך',
  english: 'a leek',
);

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap(Widget child) {
  return BlocProvider<SettingsBloc>(
    create: (_) => _TestSettingsBloc(),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('LaazEntryGroupView (דיאלוג מלא)', () {
    testWidgets(
      'מציג את כל פרטי הערך: ערך, לטינית, פירוש, מקור, הערה ואנגלית',
      (tester) async {
        await tester.pumpWidget(
          _wrap(const LaazEntryGroupView(group: [_entry])),
        );

        expect(find.text('כרתי — פוריל"ש'), findsOneWidget);
        expect(find.text('porels'), findsOneWidget);
        expect(find.text('כרשים (ירק מאכל)'), findsOneWidget);
        expect(find.text('רש"י ברכות ט:'), findsOneWidget);
        expect(find.text('הערת עורך'), findsOneWidget);
        expect(find.text('a leek'), findsOneWidget);
      },
    );

    testWidgets('לטינית ואנגלית מוצגות בכיוון LTR', (tester) async {
      await tester.pumpWidget(
        _wrap(const LaazEntryGroupView(group: [_entry])),
      );

      expect(
        tester.widget<Text>(find.text('porels')).textDirection,
        TextDirection.ltr,
      );
      expect(
        tester.widget<Text>(find.text('a leek')).textDirection,
        TextDirection.ltr,
      );
    });

    testWidgets('קבוצה ממקורות שונים מאחדת ערכים ומקורות', (tester) async {
      const second = LaazDictionaryEntry(
        entryNumber: '12',
        sourceReference: 'שבת י.',
        lemma: 'חציר',
        laazHebrew: 'פוריל"ש',
        laazLatin: 'porels',
        meaning: 'כרשים (ירק מאכל)',
      );
      await tester.pumpWidget(
        _wrap(const LaazEntryGroupView(group: [_entry, second])),
      );

      expect(find.text('כרתי, חציר — פוריל"ש'), findsOneWidget);
      expect(find.text('רש"י ברכות ט:, שבת י.'), findsOneWidget);
    });
  });

  group('LaazHoverPreviewContent (חלונית ריחוף)', () {
    testWidgets('מציגה את שם הלעז ואת הפירוש בלבד', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const LaazHoverPreviewContent(
            groups: [
              [_entry],
            ],
          ),
        ),
      );

      expect(find.text('פוריל"ש'), findsOneWidget);
      expect(
        find.textContaining('כרשים', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('porels', findRichText: true), findsNothing);
      expect(find.textContaining('רש"י', findRichText: true), findsNothing);
      expect(find.textContaining('ברכות', findRichText: true), findsNothing);
      expect(
        find.textContaining('הערת עורך', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('leek', findRichText: true), findsNothing);
    });

    testWidgets('כשאין תעתיק עברי — מוצגת מילת הערך', (tester) async {
      const noHebrew = LaazDictionaryEntry(
        entryNumber: '1',
        sourceReference: 'ברכות ט:',
        lemma: 'כרתי',
        laazHebrew: '',
        laazLatin: '',
        meaning: 'כרשים',
      );
      await tester.pumpWidget(
        _wrap(
          const LaazHoverPreviewContent(
            groups: [
              [noHebrew],
            ],
          ),
        ),
      );

      expect(find.text('כרתי'), findsOneWidget);
    });

    testWidgets('פירוש ריק — מוצג השם בלבד ללא קו מפריד', (tester) async {
      const noMeaning = LaazDictionaryEntry(
        entryNumber: '1',
        sourceReference: 'ברכות ט:',
        lemma: 'כרתי',
        laazHebrew: 'פוריל"ש',
        laazLatin: '',
        meaning: '',
      );
      await tester.pumpWidget(
        _wrap(
          const LaazHoverPreviewContent(
            groups: [
              [noMeaning],
            ],
          ),
        ),
      );

      expect(find.text('פוריל"ש'), findsOneWidget);
      expect(find.byType(Divider), findsNothing);
      expect(find.byType(SmartTextWidget), findsNothing);
    });

    testWidgets('כמה קבוצות — שורת שם ופירוש לכל קבוצה', (tester) async {
      const second = LaazDictionaryEntry(
        entryNumber: '12',
        sourceReference: 'שבת י.',
        lemma: 'חציר',
        laazHebrew: 'פוריל"ש',
        laazLatin: 'porels',
        meaning: 'עשב מאכל',
      );
      await tester.pumpWidget(
        _wrap(
          const LaazHoverPreviewContent(
            groups: [
              [_entry],
              [second],
            ],
          ),
        ),
      );

      expect(find.text('פוריל"ש'), findsNWidgets(2));
      expect(
        find.textContaining('כרשים', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('עשב מאכל', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('porels', findRichText: true), findsNothing);
    });
  });

  group('עיצוב משותף עם תצוגות הקישורים', () {
    testWidgets('כותרת, מפריד ותוכן החלונית משתמשים ב-LinkPreviewStyles', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const LaazHoverPreviewContent(
            groups: [
              [_entry],
            ],
          ),
        ),
      );

      final context = tester.element(find.byType(LaazHoverPreviewContent));
      final settings = SettingsState.initial();

      final title = tester.widget<Text>(find.text('פוריל"ש'));
      expect(
        title.style,
        LinkPreviewStyles.title(context, settings, compact: true),
      );

      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.height, LinkPreviewStyles.divider(compact: true).height);

      final content = tester.widget<SmartTextWidget>(
        find.byType(SmartTextWidget),
      );
      expect(content.settings, LinkPreviewStyles.content(settings));
    });

    testWidgets('כותרת תצוגה מקדימה של קישור משתמשת באותו LinkPreviewStyles', (
      tester,
    ) async {
      final link = Link(
        heRef: 'בראשית א',
        index1: 1,
        path2: '',
        index2: 0,
        connectionType: 'commentary',
      );
      await tester.pumpWidget(
        _wrap(LinkHoverPreviewContent(link: link, compact: true)),
      );
      await tester.pump();

      final titleFinder = find.text(link.fallbackDisplayReference);
      expect(titleFinder, findsOneWidget);
      final context = tester.element(find.byType(LinkHoverPreviewContent));
      expect(
        tester.widget<Text>(titleFinder).style,
        LinkPreviewStyles.title(
          context,
          SettingsState.initial(),
          compact: true,
        ),
      );

      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.height, LinkPreviewStyles.divider(compact: true).height);
    });

    testWidgets('חלונית הלעז וחלונית הקישור חולקות את אותה מעטפת', (
      tester,
    ) async {
      late BuildContext hostContext;
      await tester.pumpWidget(
        BlocProvider<SettingsBloc>(
          create: (_) => _TestSettingsBloc(),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  hostContext = context;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      );
      addTearDown(LinkPreviewOverlay.dismiss);

      Material panelMaterialOf(Type contentType) {
        return tester.widget<Material>(
          find
              .ancestor(
                of: find.byType(contentType),
                matching: find.byType(Material),
              )
              .first,
        );
      }

      LinkPreviewOverlay.showContent(
        hostContext,
        contentBuilder: (_) => const LaazHoverPreviewContent(
          groups: [
            [_entry],
          ],
        ),
        globalPosition: const Offset(200, 200),
        hoverMode: true,
      );
      await tester.pump();
      await tester.pump();
      final laazPanel = panelMaterialOf(LaazHoverPreviewContent);
      LinkPreviewOverlay.dismiss();
      await tester.pump();

      LinkPreviewOverlay.show(
        hostContext,
        link: Link(
          heRef: 'בראשית א',
          index1: 1,
          path2: '',
          index2: 0,
          connectionType: 'commentary',
        ),
        globalPosition: const Offset(200, 200),
        hoverMode: true,
      );
      await tester.pump();
      await tester.pump();
      final linkPanel = panelMaterialOf(LinkHoverPreviewContent);

      expect(laazPanel.color, linkPanel.color);
      expect(laazPanel.elevation, linkPanel.elevation);
      expect(laazPanel.borderRadius, linkPanel.borderRadius);
    });
  });
}
