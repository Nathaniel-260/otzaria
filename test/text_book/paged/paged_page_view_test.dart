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
    footerHeight: 10,
    sectionGap: 0,
  );
  const settings = RenderSettings(fontSize: 10, lineHeight: 1);
  const style = TextStyle(fontSize: 10, height: 1);

  /// גאומטריה זהה, עם מרווח בין־סעיפים — לבדיקת חריגה מגובה הטור.
  final gapGeometry = geometry.copyWith(sectionGap: 6);

  PagedTextMeasurer measurerFor(PageGeometry g) =>
      PagedTextMeasurer.forGeometry(
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
      measurer: measurerFor(g),
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
                measurer: measurerFor(pageGeometry),
                selectedIndices: selected,
                onLineTap: onLineTap,
              ),
            ),
          ),
        ),
      ),
    );
  }

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

    testWidgets('מספר העמוד מוצג בתחתית', (tester) async {
      final content = List.generate(6, (_) => section(10));
      final book = paginate(content);

      await pumpPage(tester, page: book.pages[1], content: content);

      expect(find.text('2'), findsOneWidget);
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
      ).measure(builderFor(content).spanFor(0)!)!;
      expect(measured.lineCount, 3);

      await pumpPage(tester, page: book.pages.first, content: content);

      final painted = tester
          .renderObjectList<RenderBox>(find.byType(RichText))
          .firstWhere((box) => box.size.width < geometry.columnWidth + 1);
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
    testWidgets('לחיצה על פרוסה מחזירה את אינדקס הסעיף', (tester) async {
      final content = [section(2), section(2)];
      final book = paginate(content);
      final taps = <int>[];

      await pumpPage(
        tester,
        page: book.pages.first,
        content: content,
        onLineTap: taps.add,
      );
      await tester.tap(find.byType(RichText).first);

      expect(taps, isNotEmpty);
      expect(taps.first, anyOf(0, 1));
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
