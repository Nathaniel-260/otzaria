import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/models/indexing_failure.dart';
import 'package:otzaria/indexing/services/indexing_failure_reporter.dart';

IndexingFailure _failure(
  String title,
  IndexingFailureKind kind, {
  StackTrace? stackTrace,
  Map<String, String> context = const {},
}) => IndexingFailure(
  bookTitle: title,
  bookPath: r'C:\lib\$title.pdf',
  kind: kind,
  rawError: 'raw error for $title',
  stackTrace: stackTrace,
  context: context,
);

void main() {
  final timestamp = DateTime.utc(2026, 8, 2, 10, 30);

  group('IndexingFailureReporter.buildReport', () {
    test('מסכם כמות, סיבת עצירה ופילוח לפי סוג', () {
      final report = IndexingFailureReporter.buildReport(
        IndexingResult.stopped(
          IndexingStopReason.abortedOnWriteFailure,
          failures: [
            _failure('א', IndexingFailureKind.fileMissing),
            _failure('ב', IndexingFailureKind.fileMissing),
            _failure('ג', IndexingFailureKind.pdfOpenFailed),
          ],
          indexedCount: 7,
        ),
        timestamp: timestamp,
      );

      expect(report, contains('כשלים: 3'));
      expect(report, contains('ספרים שאונדקסו: 7'));
      expect(report, contains('סיבת עצירה:'));
      expect(report, contains('קובץ חסר: 2'));
      expect(report, contains('PDF שלא נפתח: 1'));
    });

    test('כשל חשוד כבאג נכתב ראשון, מסומן, ועם stack trace', () {
      final report = IndexingFailureReporter.buildReport(
        IndexingResult.finished(
          failures: [
            _failure('ספר-משתמש-תקול', IndexingFailureKind.fileMissing),
            _failure(
              'ספר-חשוד-כבאג',
              IndexingFailureKind.unknown,
              stackTrace: StackTrace.fromString('#0 someFrame (file.dart:1)'),
            ),
          ],
          indexedCount: 0,
        ),
        timestamp: timestamp,
      );

      expect(report, contains('חשודים כבאג בתוכנה'));
      expect(report, contains('** חשוד כבאג בתוכנה **'));
      expect(report, contains('someFrame'));
      expect(
        report.indexOf('ספר-חשוד-כבאג'),
        lessThan(report.indexOf('ספר-משתמש-תקול')),
        reason: 'הכשל שניתן לתקן בקוד חייב להופיע לפני רעש של קבצי משתמש',
      );
    });

    test('stack trace אינו נכתב לתקלה בקובץ של המשתמש', () {
      final report = IndexingFailureReporter.buildReport(
        IndexingResult.finished(
          failures: [
            _failure(
              'PDF פגום',
              IndexingFailureKind.pdfOpenFailed,
              stackTrace: StackTrace.fromString('#0 noiseFrame (file.dart:1)'),
            ),
          ],
          indexedCount: 0,
        ),
        timestamp: timestamp,
      );

      expect(report, isNot(contains('noiseFrame')));
    });

    test('ההקשר הטכני של הספר נכתב ללוג', () {
      final report = IndexingFailureReporter.buildReport(
        IndexingResult.finished(
          failures: [
            _failure(
              'ספר',
              IndexingFailureKind.unknown,
              context: const {
                'bookType': 'PdfBook',
                'fileSize': '1234 bytes',
              },
            ),
          ],
          indexedCount: 0,
        ),
        timestamp: timestamp,
      );

      expect(report, contains('bookType: PdfBook'));
      expect(report, contains('fileSize: 1234 bytes'));
    });

    test('רשימה ענקית נחתכת ומדווחת על החיתוך', () {
      final many = List.generate(
        IndexingFailureReporter.maxDetailedFailures + 5,
        (i) => _failure('ספר $i', IndexingFailureKind.fileMissing),
      );
      final report = IndexingFailureReporter.buildReport(
        IndexingResult.finished(failures: many, indexedCount: 0),
        timestamp: timestamp,
      );

      expect(report, contains('(עוד 5 כשלים לא פורטו)'));
    });
  });

  group('IndexingFailureReporter.countByKind', () {
    test('סופר לפי סוג', () {
      final counts = IndexingFailureReporter.countByKind([
        _failure('א', IndexingFailureKind.diskFull),
        _failure('ב', IndexingFailureKind.diskFull),
        _failure('ג', IndexingFailureKind.outOfMemory),
      ]);

      expect(counts[IndexingFailureKind.diskFull], 2);
      expect(counts[IndexingFailureKind.outOfMemory], 1);
    });

    test('רשימה ריקה מחזירה מפה ריקה', () {
      expect(IndexingFailureReporter.countByKind(const []), isEmpty);
    });
  });
}
