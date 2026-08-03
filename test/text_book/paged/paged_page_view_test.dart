// טסטים לציור עמוד בודד.
//
// הטסט החשוב כאן הוא "תוכן הטור אינו עובר את הגובה שהוקצה": העימוד מדד את
// הספאנים, והציור חייב להסתדר באותם גבהים. אם הוא לא — שורה נחתכת בתחתית
// העמוד, וזה הכשל שהמשתמש רואה.

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

  String section(int lines) => List.filled(lines * 2, 'wwww').join(' ');

  PagedSectionSpanBuilder builderFor(List<String> content) =>
      PagedSectionSpanBuilder(
        content: content,
        settings: settings,
        baseStyle: style,
      );

  PaginatedBook paginate(List<String> content, {Set<int> headings = const {}}) {
    final spans = builderFor(content);
    final engine = PaginationEngine(
      geometry: geometry,
      measurer: const PagedTextMeasurer(
        width: 100,
        textScaler: TextScaler.noScaling,
        locale: Locale('he', 'IL'),
      ),
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
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: PagedPageView(
              page: page,
              geometry: pageGeometry,
              spans: builderFor(content),
              selectedIndices: selected,
              onLineTap: onLineTap,
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

    testWidgets('גאומטריה בת טור אחד מציירת טור אחד', (tester) async {
      final single = geometry.singleColumn;
      final content = [section(3)];
      final spans = builderFor(content);
      final engine = PaginationEngine(
        geometry: single,
        measurer: PagedTextMeasurer(
          width: single.columnWidth,
          textScaler: TextScaler.noScaling,
          locale: const Locale('he', 'IL'),
        ),
        sectionCount: content.length,
        buildSpan: spans.spanFor,
        isHeading: (_) => false,
      );
      engine.run();

      await pumpPage(
        tester,
        page: engine.snapshot().pages.first,
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

      // Text.rich עוטף את הספאן שלנו בספאן משלו, והרקע יושב על שורש הפרוסה —
      // ספאן בלי טקסט משלו, ולכן visitChildren אינו מגיע אליו.
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
