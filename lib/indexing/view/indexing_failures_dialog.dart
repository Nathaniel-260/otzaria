import 'package:flutter/material.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/indexing/models/indexing_failure.dart';
import 'package:otzaria/indexing/services/indexing_failure_reporter.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// מציג את הספרים שנכשלו באינדוקס, מקובצים לפי סיבה, עם ההנחיה לכל סיבה.
///
/// [totalCount] הוא מספר הכשלים בפועל — גדול מ-[failures] כשהאיסוף נחתך.
Future<void> showIndexingFailuresDialog({
  required BuildContext context,
  required List<IndexingFailure> failures,
  required int totalCount,
}) => showSingleActionDialog(
  context: context,
  title: 'ספרים שלא נכנסו לאינדקס',
  customContent: _IndexingFailuresContent(
    failures: failures,
    totalCount: totalCount,
  ),
  confirmText: 'סגור',
);

class _IndexingFailuresContent extends StatelessWidget {
  const _IndexingFailuresContent({
    required this.failures,
    required this.totalCount,
  });

  final List<IndexingFailure> failures;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final byKind = <IndexingFailureKind, List<IndexingFailure>>{};
    for (final failure in failures) {
      (byKind[failure.kind] ??= []).add(failure);
    }

    return SizedBox(
      width: 520,
      height: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$totalCount ספרים לא נכנסו לאינדקס ולא יופיעו בתוצאות החיפוש.',
            style: theme.textTheme.bodyMedium,
          ),
          if (totalCount > failures.length)
            Text(
              'מוצג פירוט של ${failures.length} מהם.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final entry in byKind.entries)
                  _KindSection(kind: entry.key, failures: entry.value),
              ],
            ),
          ),
          const Divider(height: 24),
          Text(
            'פירוט מלא נשמר בקובץ הלוג:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          SelectableText(
            ErrorLogFile.resolvePath(),
            textDirection: TextDirection.ltr,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _KindSection extends StatelessWidget {
  const _KindSection({required this.kind, required this.failures});

  final IndexingFailureKind kind;
  final List<IndexingFailure> failures;

  /// כמה ספרים לפרט לפני "ועוד N" — רשימה של אלפי ספרים אינה קריאה.
  static const int _maxListed = 15;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final listed = failures.take(_maxListed).toList();
    final omitted = failures.length - listed.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${failures.first.reason} (${failures.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            failures.first.suggestion,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          for (final failure in listed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                '• ${failure.bookTitle}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (omitted > 0)
            Text(
              'ועוד $omitted ספרים',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}

/// מציג את תקלות הבדיקה המקדימה שנמצאו לפני האינדוקס.
Future<bool?> showIndexingPreflightDialog({
  required BuildContext context,
  required List<String> titles,
  required List<String> suggestions,
  required bool hasBlocking,
}) => showTwoActionsDialog(
  context: context,
  title: hasBlocking ? 'האינדוקס צפוי להיכשל' : 'שים לב לפני האינדוקס',
  content: [
    for (var i = 0; i < titles.length; i++)
      '• ${titles[i]}\n  ${suggestions[i]}',
  ].join('\n\n'),
  cancelText: 'בטל',
  confirmText: 'המשך בכל זאת',
);

/// סיכום קצר של הכשלים לפי סוג — לשורת הסטטוס בהגדרות.
String summarizeFailures(List<IndexingFailure> failures, int totalCount) {
  if (failures.isEmpty) return '$totalCount ספרים נכשלו';
  final counts = IndexingFailureReporter.countByKind(failures);
  if (counts.length == 1) {
    return '$totalCount ספרים נכשלו: ${failures.first.reason}';
  }
  return '$totalCount ספרים נכשלו מ-${counts.length} סיבות שונות';
}
