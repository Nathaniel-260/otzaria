// טסטים לציור עמוד בודד.
//
// הטסט החשוב כאן הוא "תוכן הטור אינו עובר את הגובה שהוקצה": העימוד מדד את
// הספאנים, והציור חייב להסתדר באותם גבהים. אם הוא לא — שורה נחתכת בתחתית
// העמוד, וזה הכשל שהמשתמש רואה.
//
// הרינדור **חייב** להיות בתוך Scaffold: ב-Material יש DefaultTextStyle עם
// letterSpacing, ורק כך הטסט חי באותה סביבה שבה האפליקציה מציירת.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/paged/models/page_geometry.dart';
import 'package:otzaria/text_book/paged/models/paginated_book.dart';
import 'package:otzaria/text_book/paged/services/paged_text_measurer.dart';
import 'package:otzaria/text_book/paged/services/pagination_engine.dart';
import 'package:otzaria/text_book/paged/view/paged_page_view.dart';
import 'package:otzaria/text_book/paged/view/paged_section_spans.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

bool _anySpanHasBackground(InlineSpan span) {
  if (span.style?.backgroundColor != null) return true;
  if (span is! TextSpan) return false;
  return span.children?.any(_anySpanHasBackground) ?? false;
}

void main() {
  const geometry = PageGeometry(
    width: 240,
    height: 130,
    margins: EdgeInsets.all(10),
    columns: 2,
    columnGap: 20,
    headerHeight: 10,
    sectionGap: 0,
    headingGap: 0,
  );
  const settings = RenderSettings(fontSize: 10, lineHeight: 1);
  const style = TextStyle(fontSize: 10, height: 1);

  /// גאומטריה זהה, עם מרווח בין־סעיפים — לבדיקת חריגה מגובה הטור.
  final gapGeometry = geometry.copyWith(sectionGap: 6);

  PagedMeasurers measurerFor(PageGeometry g) => PagedMeasurers.forGeometry(
    geometry: g,
    textScaler: TextScaler.noScaling,
    locale: const Locale('he', 'IL'),
    justifyText: true,
  );

  String section(int lines) => List.filled(lines * 2, 'wwww').join(' ');

  /// טקסט שמילותיו ממלאות שורה **במדויק** (10 תווים ברוחב טור 100, גופן 10).
  /// כל תוספת מרווח בין אותיות דוחפת מילה לשורה הבאה, ולכן זה הקלט שחושף
  /// אי-התאמה בין המדידה לציור.
  String tightSection(int lines) => List.filled(lines, 'wwwwwwwwww').join(' ');

  PagedSectionSpanBuilder builderFor(
    List<String> content, {
    TextStyle? baseStyle,
  }) => PagedSectionSpanBuilder(
    content: content,
    settings: settings,
    baseStyle: baseStyle ?? style,
  );

  PaginatedBook paginate(
    List<String> content, {
    Set<int> headings = const {},
    PageGeometry? pageGeometry,
    TextStyle? baseStyle,
  }) {
    final g = pageGeometry ?? geometry;
    final spans = builderFor(content, baseStyle: baseStyle);
    final engine = PaginationEngine(
      geometry: g,
      measurers: measurerFor(g),
      sectionCount: content.length,
      buildSpan: spans.spanFor,
      isHeading: headings.contains,
    );
    engine.run();
    return engine.snapshot();
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    required BookPage page,
    required List<String> content,
    Set<int> selected = const {},
    ValueChanged<int>? onLineTap,
    PageGeometry pageGeometry = geometry,
    TextStyle? baseStyle,
    ThemeData? theme,
    String bookTitle = '',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: Center(
              child: PagedPageView(
                page: page,
                geometry: pageGeometry,
                spans: builderFor(content, baseStyle: baseStyle),
                measurers: measurerFor(pageGeometry),
                bookTitle: bookTitle,
                selectedIndices: selected,
                onLineTap: onLineTap,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder richTextWith(String needle) => find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText() == needle,
  );

  group('רצועת כותרת', () {
    /// מרווח כותרת ממשי — בלעדיו כל בדיקת מרווח הייתה עוברת גם על אפס.
    final spaced = geometry.copyWith(headingGap: 8);

    testWidgets('הכותרת פורשת על כל רוחב העמוד, והגוף על רוחב טור', (
      tester,
    ) async {
      final content = ['כותרת', 'aaaa aaaa'];
      final book = paginate(content, headings: {0}, pageGeometry: spaced);

      await pumpPage(
        tester,
        page: book.pages.first,
        content: content,
        pageGeometry: spaced,
      );

      expect(
        tester.getSize(richTextWith('כותרת')).width,
        spaced.contentWidth,
      );
      expect(
        tester.getSize(richTextWith('aaaa aaaa')).width,
        spaced.columnWidth,
      );
    });

    testWidgets('המרווח הוא מעל הכותרת ולא מתחתיה', (tester) async {
      final content = ['aaaa aaaa', 'כותרת', 'bbbb bbbb'];
      final book = paginate(content, headings: {1}, pageGeometry: spaced);

      await pumpPage(
        tester,
        page: book.pages.first,
        content: content,
        pageGeometry: spaced,
      );

      final above = tester.getRect(richTextWith('aaaa aaaa'));
      final heading = tester.getRect(richTextWith('כותרת'));
      final below = tester.getRect(richTextWith('bbbb bbbb'));

      expect(heading.top - above.bottom, closeTo(spaced.headingGap, 0.01));
      expect(below.top - heading.bottom, closeTo(0, 0.01));
    });

    testWidgets('הכותרת ממורכזת', (tester) async {
      final content = ['כותרת', 'aaaa aaaa'];
      final book = paginate(content, headings: {0}, pageGeometry: spaced);

      await pumpPage(
        tester,
        page: book.pages.first,
        content: content,
        pageGeometry: spaced,
      );

      final page = tester.getRect(find.byType(PagedPageView));
      final heading = tester.getRect(richTextWith('כותרת'));

      expect(heading.center.dx, closeTo(page.center.dx, 0.01));
    });

    testWidgets('עמוד עם כותרות אינו חורג מגובהו', (tester) async {
      final content = [
        for (var i = 0; i < 14; i++)
          if (i.isEven) 'כותרת $i' else section(3),
      ];
      final book = paginate(
        content,
        headings: {for (var i = 0; i < 14; i += 2) i},
        pageGeometry: spaced,
      );

      for (final page in book.pages) {
        await pumpPage(
          tester,
          page: page,
          content: content,
          pageGeometry: spaced,
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'עמוד ${page.number} חרג מגובהו',
        );
      }
    });
  });

  group('פריסת העמוד', () {
    testWidgets('גודל העמוד הוא בדיוק הגאומטריה', (tester) async {
      final content = [section(3)];
      final book = paginate(content);

      await pumpPage(tester, page: book.pages.first, content: content);

      expect(
        tester.getSize(find.byType(PagedPageView)),
        const Size(240, 130),
      );
    });

    testWidgets('הכותרת הרצה מציגה את שם הספר ומספר העמוד באותיות', (
      tester,
    ) async {
      final content = List.generate(6, (_) => section(10));
      final book = paginate(content);

      await pumpPage(
        tester,
        page: book.pages[1],
        content: content,
        bookTitle: 'בראשית',
      );

      expect(find.text('בראשית'), findsOneWidget);
      expect(find.text('ב'), findsOneWidget);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('הכותרת הרצה אינה נכנסת לטקסט המועתק', (tester) async {
      final content = [section(2)];
      final book = paginate(content);

      await pumpPage(
        tester,
        page: book.pages.first,
        content: content,
        bookTitle: 'בראשית',
      );

      expect(
        find.ancestor(
          of: find.text('בראשית'),
          matching: find.byType(SelectionContainer),
        ),
        findsWidgets,
      );
    });

    testWidgets('רוחב כל טור הוא רוחב הטור שהעימוד מדד בו', (tester) async {
      final content = List.generate(4, (_) => section(5));
      final book = paginate(content);

      await pumpPage(tester, page: book.pages.first, content: content);

      final texts = tester.widgetList<RichText>(find.byType(RichText));
      final columnTexts = texts.where(
        (text) => text.text.toPlainText().contains('wwww'),
      );
      expect(columnTexts, isNotEmpty);
      for (final text in columnTexts) {
        final element = find.byWidget(text).evaluate().first;
        expect(
          (element.renderObject as RenderBox).size.width,
          closeTo(geometry.columnWidth, 0.01),
        );
      }
    });

    testWidgets('רוחב הטור אינו נגרר אחרי רוחב החלון', (tester) async {
      // המידה חייבת להיות מפורשת ולא גמישה: טור שנמתח לפי המקום הפנוי היה
      // שובר שורות במקום אחר מזה שהעימוד מדד, ושורה הייתה נחתכת בתחתית.
      final content = List.generate(4, (_) => section(5));
      final book = paginate(content);

      for (final available in [geometry.width * 3, geometry.width * 0.6]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Directionality(
                textDirection: TextDirection.rtl,
                child: SizedBox(
                  width: available,
                  // כמו בתצוגה עצמה: העמוד שומר על גודלו והחלון נגלל אליו.
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: PagedPageView(
                      page: book.pages.first,
                      geometry: geometry,
                      spans: builderFor(content),
                      measurers: measurerFor(geometry),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final text = tester
            .widgetList<RichText>(find.byType(RichText))
            .firstWhere((t) => t.text.toPlainText().contains('wwww'));
        final box =
            find.byWidget(text).evaluate().first.renderObject as RenderBox;

        expect(
          box.size.width,
          closeTo(geometry.columnWidth, 0.01),
          reason: 'ברוחב חלון $available',
        );
      }
    });

    testWidgets('תוכן הטור אינו עובר את הגובה שהוקצה לו', (tester) async {
      final content = List.generate(12, (i) => section(3 + i % 5));
      final book = paginate(content);

      for (final page in book.pages) {
        await pumpPage(tester, page: page, content: content);

        // RenderFlex מהדק את גודלו לאילוץ, ולכן בדיקת גובה לבדה אינה מזהה
        // חריגה — רק חריגת הפריסה עצמה מזהה.
        expect(
          tester.takeException(),
          isNull,
          reason: 'עמוד ${page.number} חורג',
        );
        for (final columnBox in tester.renderObjectList<RenderBox>(
          find.byType(Column),
        )) {
          if (columnBox.size.width > geometry.columnWidth + 1) continue;
          expect(
            columnBox.size.height,
            lessThanOrEqualTo(geometry.contentHeight + 0.5),
            reason: 'עמוד ${page.number}',
          );
        }
      }
    });

    testWidgets('מרווח בין־סעיפים אינו מוציא את הטור מגבולותיו', (
      tester,
    ) async {
      // 12 סעיפים בני שתי שורות עם מרווח 6: בלי הכלל שהמרווח הוא מפריד ולא
      // זנב, הטור היה מגיע ל-104 בתוך גובה 100.
      final content = List.generate(12, (_) => section(2));
      final book = paginate(content, pageGeometry: gapGeometry);

      for (final page in book.pages) {
        await pumpPage(
          tester,
          page: page,
          content: content,
          pageGeometry: gapGeometry,
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'עמוד ${page.number} חורג',
        );
      }
    });

    testWidgets('גובה הפרוסה בציור זהה לגובה שנמדד — גם בתוך Material', (
      tester,
    ) async {
      // Material מגדיר DefaultTextStyle עם letterSpacing. ציור שיורש אותו שובר
      // שורות מוקדם יותר מהמדידה, וכל טור מאבד שורה בתחתיתו.
      final content = [tightSection(3)];
      final book = paginate(content);
      final measured = measurerFor(
        geometry,
      ).body.measure(builderFor(content).spanFor(0)!)!;
      expect(measured.lineCount, 3);

      await pumpPage(tester, page: book.pages.first, content: content);

      // הסינון לפי התוכן ולא לפי הרוחב: הכותרת הרצה היא גם היא RichText צר.
      final slice = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((text) => text.text.toPlainText().contains('wwww'));
      final painted =
          find.byWidget(slice).evaluate().first.renderObject as RenderBox;
      expect(painted.size.height, closeTo(measured.totalHeight, 0.01));
    });

    testWidgets('גאומטריה בת טור אחד מציירת טור אחד', (tester) async {
      final single = geometry.singleColumn;
      final content = [section(3)];
      final book = paginate(content, pageGeometry: single);

      await pumpPage(
        tester,
        page: book.pages.first,
        content: content,
        pageGeometry: single,
      );

      expect(
        tester.getSize(find.byType(PagedPageView)),
        const Size(240, 130),
      );
    });
  });

  group('אינטראקציה', () {
    testWidgets('לחיצה על פרוסה מחזירה את אינדקס הסעיף שנלחץ', (tester) async {
      // שלושה סעיפים בעלי טקסט שונה, כדי שהטסט יבדיל בין מיפוי נכון למיפוי
      // שמחזיר תמיד את הראשון.
      final content = ['אאאא אאאא', 'בבבב בבבב', 'גגגג גגגג'];
      final book = paginate(content);
      final taps = <int>[];

      await pumpPage(
        tester,
        page: book.pages.first,
        content: content,
        onLineTap: taps.add,
      );

      for (final entry in {0: 'אאאא', 1: 'בבבב', 2: 'גגגג'}.entries) {
        final target = find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains(entry.value),
        );
        await tester.tap(target);
        expect(taps.last, entry.key, reason: 'לחיצה על ${entry.value}');
      }

      expect(taps, [0, 1, 2]);
    });

    testWidgets('סעיף מסומן מקבל רקע', (tester) async {
      final content = [section(2)];
      final book = paginate(content);

      await pumpPage(
        tester,
        page: book.pages.first,
        content: content,
        selected: const {0},
      );

      // הרקע יושב על שורש הפרוסה — ספאן בלי טקסט משלו, ולכן visitChildren
      // אינו מגיע אליו.
      final root = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((t) => t.text.toPlainText().contains('wwww'))
          .text;

      expect(_anySpanHasBackground(root), isTrue);
    });

    testWidgets('סעיף שאינו מסומן אינו מקבל רקע', (tester) async {
      // המקרה השלילי: בלעדיו טסט הסימון היה עובר גם אם כל פרוסה נצבעת.
      final content = [section(2), section(2)];
      final book = paginate(content);

      await pumpPage(
        tester,
        page: book.pages.first,
        content: content,
        selected: const {},
      );

      final painted = tester
          .widgetList<RichText>(find.byType(RichText))
          .where((text) => text.text.toPlainText().contains('wwww'));

      expect(painted, isNotEmpty);
      for (final text in painted) {
        expect(_anySpanHasBackground(text.text), isFalse);
      }
    });

    testWidgets('סעיף אחר מסומן — רק הוא מקבל רקע', (tester) async {
      final content = ['אאאא אאאא', 'בבבב בבבב'];
      final book = paginate(content);

      await pumpPage(
        tester,
        page: book.pages.first,
        content: content,
        selected: const {1},
      );

      final byText = {
        for (final text in tester.widgetList<RichText>(find.byType(RichText)))
          text.text.toPlainText(): text.text,
      };
      final first = byText.entries.firstWhere((e) => e.key.contains('אאאא'));
      final second = byText.entries.firstWhere((e) => e.key.contains('בבבב'));

      expect(_anySpanHasBackground(first.value), isFalse);
      expect(_anySpanHasBackground(second.value), isTrue);
    });

    testWidgets('בלי מטפל לחיצה אין GestureDetector על הטקסט', (tester) async {
      final content = [section(2)];
      final book = paginate(content);

      await pumpPage(tester, page: book.pages.first, content: content);

      expect(find.byType(GestureDetector), findsNothing);
    });
  });

  group('צבע הטקסט', () {
    testWidgets('הצבע מגיע מהערכה ואינו מתלכד עם רקע העמוד', (tester) async {
      // RichText אינו יורש DefaultTextStyle, וספאן בלי צבע מצויר בלבן — על
      // רקע העמוד הבהיר זה טקסט בלתי נראה.
      final theme = ThemeData(colorScheme: const ColorScheme.light());
      final baseStyle = PagedSectionSpanBuilder.baseStyleFor(
        settings,
        theme.colorScheme,
      );
      final content = [section(2)];
      final book = paginate(content, baseStyle: baseStyle);

      await pumpPage(
        tester,
        page: book.pages.first,
        content: content,
        baseStyle: baseStyle,
        theme: theme,
      );

      final root = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((text) => text.text.toPlainText().contains('wwww'))
          .text;

      expect(root.style?.color, isNotNull);
      expect(root.style!.color, isNot(theme.colorScheme.surface));
      expect(root.style!.color, theme.colorScheme.onSurface);
    });

    testWidgets('הצבע עוקב אחרי ערכה כהה', (tester) async {
      final theme = ThemeData(colorScheme: const ColorScheme.dark());
      final baseStyle = PagedSectionSpanBuilder.baseStyleFor(
        settings,
        theme.colorScheme,
      );
      final content = [section(2)];
      final book = paginate(content, baseStyle: baseStyle);

      await pumpPage(
        tester,
        page: book.pages.first,
        content: content,
        baseStyle: baseStyle,
        theme: theme,
      );

      final root = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((text) => text.text.toPlainText().contains('wwww'))
          .text;

      expect(root.style!.color, theme.colorScheme.onSurface);
      expect(root.style!.color, isNot(theme.colorScheme.surface));
    });
  });

  testWidgets('פרוסות של אותו סעיף בשני טורים מציגות טקסט משלים', (
    tester,
  ) async {
    final content = [section(14)];
    final book = paginate(content);
    final page = book.pages.first;

    await pumpPage(tester, page: page, content: content);

    final rendered = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((text) => text.text.toPlainText())
        .where((text) => text.contains('wwww'))
        .toList();

    expect(rendered, hasLength(2));
    expect(rendered[0], isNot(rendered[1]));
  });
}
