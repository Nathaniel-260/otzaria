import 'package:flutter/material.dart';
import 'package:otzaria/text_book/paged/models/page_geometry.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart'
    show numberToHebrewWithoutQuotes;
import 'package:otzaria/text_book/paged/models/paginated_book.dart';
import 'package:otzaria/text_book/paged/services/paged_text_measurer.dart';
import 'package:otzaria/text_book/paged/view/paged_section_spans.dart';

/// עובי הקווים בעמוד — הקו שמתחת לכותרת הרצה, והמפריד בין הטורים.
const double _ruleThickness = 0.7;

/// חלקו של הרווח שמתחת לקו מתוך גובה הכותרת הרצה. יחסי ולא מוחלט, אחרת
/// גאומטריה עם כותרת נמוכה הייתה מקבלת רווח גדול מהמקום שיש לו.
const double _headerRuleGapRatio = 1 / 3;

/// הקו שבין הטורים אינו נוגע בקצות אזור התוכן.
const double _columnRuleInset = 4;

/// עמוד פיזי אחד.
///
/// כל המידות מפורשות: רוחב הטור מגיע מ-[PageGeometry.columnWidth] ולא מ-`Expanded`,
/// כי זה בדיוק הרוחב שהעימוד מדד בו. חלוקה אחרת של הרוחב תשבור שורות במקום אחר
/// מזה שחושב, ושורה תיחתך בתחתית העמוד.
class PagedPageView extends StatelessWidget {
  final BookPage page;
  final PageGeometry geometry;
  final PagedSectionSpanBuilder spans;

  /// אותם מודדים שהעימוד השתמש בהם. הציור עובר דרכם כדי שפרמטרי הפריסה יהיו
  /// זהים — ראו [PagedTextMeasurer.buildText].
  final PagedMeasurers measurers;

  /// שורות מסומנות — מקבלות רקע. צבע רקע אינו משנה מטריקות, ולכן מותר להוסיף
  /// אותו רק בציור.
  final Set<int> selectedIndices;

  final ValueChanged<int>? onLineTap;

  /// שם הספר, בכותרת הרצה שבראש העמוד.
  final String bookTitle;

  const PagedPageView({
    super.key,
    required this.page,
    required this.geometry,
    required this.spans,
    required this.measurers,
    this.bookTitle = '',
    this.selectedIndices = const {},
    this.onLineTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: geometry.width,
      height: geometry.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(color: colorScheme.surfaceContainerHighest),
        ),
        child: Padding(
          padding: geometry.margins,
          child: Column(
            children: [
              _buildHeader(context, colorScheme),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _bandsWithGaps(context, colorScheme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// הכותרת הרצה: שם הספר ומספר העמוד באותיות, מעל שני הטורים, ומתחתיה קו.
  ///
  /// מוחרגת מהבחירה — בלי זה כל העתקה שמגיעה לראש עמוד גורפת את שם הספר ואת
  /// מספר העמוד אל תוך הטקסט המועתק.
  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    return SizedBox(
      height: geometry.headerHeight,
      child: SelectionContainer.disabled(
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      bookTitle,
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(numberToHebrewWithoutQuotes(page.number), style: style),
                ],
              ),
            ),
            Container(
              height: _ruleThickness,
              color: colorScheme.outlineVariant,
            ),
            SizedBox(height: geometry.headerHeight * _headerRuleGapRatio),
          ],
        ),
      ),
    );
  }

  List<Widget> _bandsWithGaps(BuildContext context, ColorScheme colorScheme) {
    final children = <Widget>[];
    PageBand? previous;
    for (final band in page.bands) {
      final gap = PageBand.gapBefore(band, previous, geometry);
      if (gap > 0) children.add(SizedBox(height: gap));
      children.add(switch (band) {
        HeadingBand(slice: final slice) =>
          _buildSlice(context, slice, colorScheme, measurers.heading) ??
              const SizedBox.shrink(),
        ColumnsBand(columns: final columns) => _buildColumnsBand(
          context,
          columns,
          colorScheme,
        ),
      });
      previous = band;
    }
    return children;
  }

  /// רצועת גוף. הקווים בין הטורים מצוירים על גובה הרצועה בפועל, ולכן הם
  /// נגמרים עם הטקסט ואינם נמשכים אל תוך שטח ריק.
  Widget _buildColumnsBand(
    BuildContext context,
    List<PageColumn> columns,
    ColorScheme colorScheme,
  ) {
    final children = <Widget>[];
    for (var i = 0; i < columns.length; i++) {
      if (i > 0) children.add(SizedBox(width: geometry.columnGap));
      children.add(
        SizedBox(
          width: geometry.columnWidth,
          child: _buildColumn(context, columns[i], colorScheme),
        ),
      );
    }

    return CustomPaint(
      painter: _ColumnRulesPainter(
        geometry: geometry,
        color: colorScheme.outlineVariant,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildColumn(
    BuildContext context,
    PageColumn column,
    ColorScheme colorScheme,
  ) {
    final children = <Widget>[];
    var previousEndedSection = false;

    for (final slice in column.slices) {
      final widget = _buildSlice(context, slice, colorScheme, measurers.body);
      if (widget != null) {
        // המרווח הוא מפריד **בין** סעיפים ולא זנב אחרי האחרון: המנוע מרשה
        // לעצמו לחרוג מגובה הטור במרווח הסופי (הסעיף הבא עובר לטור הבא),
        // אבל בציור הטור חסום בגובה קבוע והזנב היה מוציא אותו מגבולותיו.
        if (children.isNotEmpty &&
            previousEndedSection &&
            geometry.sectionGap > 0) {
          children.add(SizedBox(height: geometry.sectionGap));
        }
        children.add(widget);
      }
      previousEndedSection = !slice.continuesNext;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget? _buildSlice(
    BuildContext context,
    PageSlice slice,
    ColorScheme colorScheme,
    PagedTextMeasurer measurer,
  ) {
    if (slice.isEmpty) return null;
    final full = spans.spanFor(slice.sourceIndex);
    if (full == null) return null;

    final sliced = sliceInlineSpan(full, slice.charStart, slice.charEnd);
    if (sliced == null) return null;

    final text = measurer.buildText(
      selectedIndices.contains(slice.sourceIndex)
          ? _withBackground(sliced, colorScheme.primaryContainer)
          : sliced,
      // RichText אינו שואב את צבע הבחירה לבד, ולכן הוא מגיע מכאן. הצבע עצמו
      // מוגדר ב-lib/theme בלבד.
      selectionRegistrar: SelectionContainer.maybeOf(context),
      selectionColor:
          DefaultSelectionStyle.of(context).selectionColor ??
          Theme.of(context).textSelectionTheme.selectionColor,
    );

    final onTap = onLineTap;
    if (onTap == null) return text;
    return GestureDetector(
      onTap: () => onTap(slice.sourceIndex),
      child: text,
    );
  }

  /// עוטף את הפרוסה ברקע. הרקע מוגדר על ה-root בלבד; ספאן פנימי עם רקע משלו
  /// (הדגשת חיפוש) שומר עליו.
  InlineSpan _withBackground(InlineSpan span, Color background) {
    if (span is! TextSpan) return span;
    return TextSpan(
      text: span.text,
      children: span.children,
      style: (span.style ?? const TextStyle()).copyWith(
        backgroundColor: background,
      ),
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }
}

/// הקווים שבין הטורים, באמצע המרווח שביניהם. אינם נוגעים בקצות הרצועה.
class _ColumnRulesPainter extends CustomPainter {
  final PageGeometry geometry;
  final Color color;

  const _ColumnRulesPainter({required this.geometry, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final top = _columnRuleInset;
    final bottom = size.height - _columnRuleInset;
    if (bottom <= top) return;

    final paint = Paint()..color = color;
    for (var i = 0; i < geometry.columns - 1; i++) {
      final center = geometry.columnRuleCenter(i);
      canvas.drawRect(
        Rect.fromLTRB(
          center - _ruleThickness / 2,
          top,
          center + _ruleThickness / 2,
          bottom,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ColumnRulesPainter oldDelegate) =>
      oldDelegate.geometry != geometry || oldDelegate.color != color;
}
