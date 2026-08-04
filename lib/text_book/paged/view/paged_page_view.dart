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

  /// אותו מודד שהעימוד השתמש בו. הציור עובר דרכו כדי שפרמטרי הפריסה יהיו
  /// זהים — ראו [PagedTextMeasurer.buildText].
  final PagedTextMeasurer measurer;

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
    required this.measurer,
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
              SizedBox(
                height: geometry.contentHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _columnsWithGaps(context, colorScheme),
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

  List<Widget> _columnsWithGaps(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    final children = <Widget>[];
    for (var i = 0; i < page.columns.length; i++) {
      if (i > 0) children.add(_columnDivider(colorScheme));
      children.add(
        SizedBox(
          width: geometry.columnWidth,
          child: _buildColumn(context, page.columns[i], colorScheme),
        ),
      );
    }
    return children;
  }

  /// קו מפריד באמצע המרווח שבין הטורים. אינו נוגע בקצות אזור התוכן.
  Widget _columnDivider(ColorScheme colorScheme) => SizedBox(
    width: geometry.columnGap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: _columnRuleInset),
      child: Center(
        child: SizedBox(
          width: _ruleThickness,
          height: double.infinity,
          child: ColoredBox(color: colorScheme.outlineVariant),
        ),
      ),
    ),
  );

  Widget _buildColumn(
    BuildContext context,
    PageColumn column,
    ColorScheme colorScheme,
  ) {
    final children = <Widget>[];
    var previousEndedSection = false;

    for (final slice in column.slices) {
      final widget = _buildSlice(context, slice, colorScheme);
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
