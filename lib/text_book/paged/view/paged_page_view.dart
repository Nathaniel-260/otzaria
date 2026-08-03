import 'package:flutter/material.dart';
import 'package:otzaria/text_book/paged/models/page_geometry.dart';
import 'package:otzaria/text_book/paged/models/paginated_book.dart';
import 'package:otzaria/text_book/paged/services/paged_text_measurer.dart';
import 'package:otzaria/text_book/paged/view/paged_section_spans.dart';

/// עמוד פיזי אחד.
///
/// כל המידות מפורשות: רוחב הטור מגיע מ-[PageGeometry.columnWidth] ולא מ-`Expanded`,
/// כי זה בדיוק הרוחב שהעימוד מדד בו. חלוקה אחרת של הרוחב תשבור שורות במקום אחר
/// מזה שחושב, ושורה תיחתך בתחתית העמוד.
class PagedPageView extends StatelessWidget {
  final BookPage page;
  final PageGeometry geometry;
  final PagedSectionSpanBuilder spans;
  final TextAlign textAlign;

  /// שורות מסומנות — מקבלות רקע. צבע רקע אינו משנה מטריקות, ולכן מותר להוסיף
  /// אותו רק בציור.
  final Set<int> selectedIndices;

  final ValueChanged<int>? onLineTap;

  const PagedPageView({
    super.key,
    required this.page,
    required this.geometry,
    required this.spans,
    this.textAlign = TextAlign.justify,
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
              SizedBox(
                height: geometry.contentHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _columnsWithGaps(colorScheme),
                ),
              ),
              SizedBox(
                height: geometry.footerHeight,
                child: Center(
                  child: Text(
                    '${page.number}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _columnsWithGaps(ColorScheme colorScheme) {
    final children = <Widget>[];
    for (var i = 0; i < page.columns.length; i++) {
      if (i > 0) children.add(SizedBox(width: geometry.columnGap));
      children.add(
        SizedBox(
          width: geometry.columnWidth,
          child: _buildColumn(page.columns[i], colorScheme),
        ),
      );
    }
    return children;
  }

  Widget _buildColumn(PageColumn column, ColorScheme colorScheme) {
    final children = <Widget>[];
    for (final slice in column.slices) {
      final widget = _buildSlice(slice, colorScheme);
      if (widget != null) children.add(widget);
      // המרווח מתווסף רק אחרי פרוסה שמסיימת סעיף — כך העימוד חישב אותו.
      if (!slice.continuesNext && geometry.sectionGap > 0) {
        children.add(SizedBox(height: geometry.sectionGap));
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget? _buildSlice(PageSlice slice, ColorScheme colorScheme) {
    if (slice.isEmpty) return null;
    final full = spans.spanFor(slice.sourceIndex);
    if (full == null) return null;

    final sliced = sliceInlineSpan(full, slice.charStart, slice.charEnd);
    if (sliced == null) return null;

    final text = Text.rich(
      selectedIndices.contains(slice.sourceIndex)
          ? _withBackground(sliced, colorScheme.primaryContainer)
          : sliced,
      textAlign: textAlign,
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
