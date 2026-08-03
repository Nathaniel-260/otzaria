import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/models/indexing_failure.dart';

void main() {
  group('IndexingFailure.classify', () {
    test('דיסק מלא מזוהה בניסוחים של Windows ושל POSIX', () {
      expect(
        IndexingFailure.classify(
          'FileSystemException: There is not enough space on the disk',
        ),
        IndexingFailureKind.diskFull,
      );
      expect(
        IndexingFailure.classify('OS Error: No space left on device, errno=28'),
        IndexingFailureKind.diskFull,
      );
    });

    test('חוסר הרשאות מזוהה ולא מסווג כקובץ חסר', () {
      expect(
        IndexingFailure.classify(
          'FileSystemException: Cannot open file, OS Error: Access is denied',
        ),
        IndexingFailureKind.permissionDenied,
      );
    });

    test('קובץ חסר מזוהה', () {
      expect(
        IndexingFailure.classify(
          'PathNotFoundException: Cannot find the file specified',
        ),
        IndexingFailureKind.fileMissing,
      );
    });

    test('timeout מסווג ככשל פתיחה — הספר לא נכנס לאינדקס כלל', () {
      // רגרסיה מלוג אמיתי: timeout בפתיחת המסמך סווג כ"אונדקס חלקית",
      // והמשתמש קיבל הנחיה על ספר שכלל לא נכנס לאינדקס.
      expect(
        IndexingFailure.classify('TimeoutException after 0:01:00.000000'),
        IndexingFailureKind.pdfOpenTimeout,
      );
    });

    test('RangeError מתוך pdfrx = כשל טעינה קבוע', () {
      // מלוג אמיתי: אותם קבצים חזרו על RangeError גם אחרי שהסריאליזציה
      // חיסלה את ה-timeouts — כולל קובץ של 0.5MB. כלומר זה כשל טעינה
      // של pdfrx, לא קורבן של מגבלת הזמן.
      final stack = StackTrace.fromString(
        '#0 _PdfDocumentPdfium._loadPagesInLimitedTime '
        '(package:pdfrx_engine/src/native/pdfrx_pdfium.dart)',
      );
      expect(
        IndexingFailure.classify(
          'RangeError (length): Invalid value: Not in inclusive range 0..3: -1',
          stack,
        ),
        IndexingFailureKind.pdfLoadUnsupported,
      );
      // בלי ה-stack אין דרך לדעת שזה pdfrx — נשאר unknown.
      expect(
        IndexingFailure.classify(
          'RangeError (length): Invalid value: Not in inclusive range 0..3: -1',
        ),
        IndexingFailureKind.unknown,
      );
    });

    test('Future.timeout ב-stack אינו מסווג שגיאה כ-timeout', () {
      // רגרסיה חמורה מלוג אמיתי: הסיווג חיפש 'Future.timeout' ב-stack,
      // אבל ‎.timeout()‎ נמצא בשרשרת של כל פתיחה — כך שכל 43 הכשלים
      // סווגו כ-timeout זמני, קבצים מוצפנים לא נרשמו כמעובדים, וחזרו
      // בכל ריצה. שלוש ריצות רצופות יצאו זהות לחלוטין.
      final stack = StackTrace.fromString(
        '#0 Future.timeout.<anonymous closure> '
        '(dart:async/future_impl.dart:1061)\n'
        '#1 _PdfDocumentPdfium.fromPdfDocument '
        '(package:pdfrx_engine/src/native/pdfrx_pdfium.dart:1056)',
      );
      final kind = IndexingFailure.classify(
        'PdfException: No password supplied by PasswordProvider.',
        stack,
      );
      expect(kind, IndexingFailureKind.pdfOpenFailed);
      expect(kind.isPermanent, isTrue, reason: 'מוצפן — אין טעם לנסות שוב');
    });

    test('כשל קבוע מובחן מכשל שווה-ניסיון-חוזר', () {
      // קובץ מוצפן/חסר לא ישתנה בריצה חוזרת; עומס וזיכרון כן.
      for (final kind in [
        IndexingFailureKind.pdfOpenFailed,
        IndexingFailureKind.fileMissing,
        IndexingFailureKind.pdfLoadUnsupported,
      ]) {
        expect(kind.isPermanent, isTrue, reason: '$kind קבוע');
      }
      for (final kind in [
        IndexingFailureKind.pdfOpenTimeout,
        IndexingFailureKind.pdfTextTimeout,
        IndexingFailureKind.diskFull,
        IndexingFailureKind.outOfMemory,
        IndexingFailureKind.permissionDenied,
        IndexingFailureKind.engineWriteFailed,
        IndexingFailureKind.unknown,
      ]) {
        expect(kind.isPermanent, isFalse, reason: '$kind שווה ניסיון חוזר');
      }
    });

    test('כשל פתיחת PDF מזוהה, כולל קובץ מוגן בסיסמה', () {
      expect(
        IndexingFailure.classify('PdfException: failed to load pdf document'),
        IndexingFailureKind.pdfOpenFailed,
      );
      expect(
        IndexingFailure.classify('Document requires a password'),
        IndexingFailureKind.pdfOpenFailed,
      );
    });

    test('פאניקה של המנוע מסווגת ככשל כתיבה', () {
      expect(
        IndexingFailure.classify('PanicException(SchemaError("mismatch"))'),
        IndexingFailureKind.engineWriteFailed,
      );
    });

    test('שגיאה לא מוכרת נופלת ל-unknown', () {
      expect(
        IndexingFailure.classify('Bad state: something odd'),
        IndexingFailureKind.unknown,
      );
    });

    test('דיסק מלא גובר על אזכור נתיב קובץ באותה הודעה', () {
      // סדר הבדיקות קובע — הודעה אחת נושאת כמה סימנים, והספציפי מנצח.
      expect(
        IndexingFailure.classify(
          'FileSystemException: Cannot open file, no space left on device',
        ),
        IndexingFailureKind.diskFull,
      );
    });
  });

  group('IndexingFailure — סימון באג בתוכנה', () {
    test('unknown ו-engineWriteFailed מסומנים כחשודים כבאג', () {
      for (final kind in [
        IndexingFailureKind.unknown,
        IndexingFailureKind.engineWriteFailed,
      ]) {
        expect(
          IndexingFailure(
            bookTitle: 'ספר',
            kind: kind,
            rawError: 'x',
          ).isLikelyAppBug,
          isTrue,
          reason: '$kind אמור להיות מסומן כבאג',
        );
      }
    });

    test('תקלה בקובץ של המשתמש אינה מסומנת כבאג בתוכנה', () {
      for (final kind in [
        IndexingFailureKind.fileMissing,
        IndexingFailureKind.pdfOpenFailed,
        IndexingFailureKind.diskFull,
        IndexingFailureKind.permissionDenied,
      ]) {
        expect(
          IndexingFailure(
            bookTitle: 'ספר',
            kind: kind,
            rawError: 'x',
          ).isLikelyAppBug,
          isFalse,
          reason: '$kind אינו באג בתוכנה',
        );
      }
    });

    test('לכל סוג כשל יש סיבה והנחיה לא ריקות', () {
      for (final kind in IndexingFailureKind.values) {
        final failure = IndexingFailure(
          bookTitle: 'ספר',
          kind: kind,
          rawError: 'x',
        );
        expect(failure.reason, isNotEmpty);
        expect(failure.suggestion, isNotEmpty);
      }
    });
  });

  group('IndexingFailureCollector', () {
    test('שומר את הכשלים עד התקרה אך סופר את כולם', () {
      // רגרסיה: כונן שנותק באמצע אינדוקס של עשרות אלפי ספרים צבר אובייקט
      // כשל עם stack trace לכל ספר — מאות MB עד קריסה.
      final collector = IndexingFailureCollector();
      final overflow = IndexingFailureCollector.maxCollected + 250;
      for (var i = 0; i < overflow; i++) {
        collector.add(
          IndexingFailure(
            bookTitle: 'ספר $i',
            kind: IndexingFailureKind.fileMissing,
            rawError: 'x',
          ),
        );
      }

      expect(collector.total, overflow);
      expect(
        collector.collected,
        hasLength(IndexingFailureCollector.maxCollected),
      );
      expect(collector.collected.first.bookTitle, 'ספר 0');
    });

    test('dropFor מפחית רק את מה שהוסר בפועל', () {
      final collector = IndexingFailureCollector();
      for (final path in ['a', 'b', 'c']) {
        collector.add(
          IndexingFailure(
            bookTitle: path,
            bookPath: path,
            kind: IndexingFailureKind.pdfOpenTimeout,
            rawError: 'x',
          ),
        );
      }

      collector.dropFor({'a', 'לא-קיים'});

      expect(collector.total, 2);
      expect(collector.collected.map((f) => f.bookPath), ['b', 'c']);
    });

    test('אוסף שנחתך: dropFor משאיר מונה חי עם רשימה ריקה', () {
      // רגרסיה: הרשימה התרוקנה אך המונה נשאר > 0, ו-finished קבע את
      // הסיבה לפי הרשימה — כך ריצה עם ספרים חסרים דווחה "הושלם במלואו".
      final collector = IndexingFailureCollector();
      final overflow = IndexingFailureCollector.maxCollected + 20;
      for (var i = 0; i < overflow; i++) {
        collector.add(
          IndexingFailure(
            bookTitle: 'ספר $i',
            bookPath: 'p$i',
            kind: IndexingFailureKind.pdfOpenTimeout,
            rawError: 'x',
          ),
        );
      }
      collector.dropFor({
        for (var i = 0; i < overflow; i++) 'p$i',
      });

      expect(collector.collected, isEmpty);
      expect(collector.total, 20, reason: '20 לא נאספו ולכן לא הוסרו');

      final result = IndexingResult.finished(
        failures: collector.collected,
        totalFailures: collector.total,
        indexedCount: 0,
      );
      expect(result.reason, IndexingStopReason.completedWithFailures);
      expect(result.isFullyComplete, isFalse);
    });

    test('אוסף ריק', () {
      final collector = IndexingFailureCollector();
      expect(collector.isEmpty, isTrue);
      expect(collector.total, 0);
      expect(collector.collected, isEmpty);
    });
  });

  group('IndexingResult', () {
    test('ריצה בלי כשלים היא completed', () {
      final result = IndexingResult.finished(
        failures: const [],
        indexedCount: 5,
      );
      expect(result.reason, IndexingStopReason.completed);
      expect(result.isFullyComplete, isTrue);
      expect(result.didFinish, isTrue);
      expect(result.stopMessage, isNull);
    });

    test('ריצה עם כשלים הסתיימה אך אינה שלמה', () {
      final result = IndexingResult.finished(
        failures: const [
          IndexingFailure(
            bookTitle: 'ספר',
            kind: IndexingFailureKind.fileMissing,
            rawError: 'x',
          ),
        ],
        indexedCount: 4,
      );
      expect(result.reason, IndexingStopReason.completedWithFailures);
      expect(result.didFinish, isTrue);
      expect(result.isFullyComplete, isFalse);
    });

    test('failureCount משקף את המונה האמיתי גם כשהפירוט נחתך', () {
      final result = IndexingResult.finished(
        failures: const [
          IndexingFailure(
            bookTitle: 'ספר',
            kind: IndexingFailureKind.fileMissing,
            rawError: 'x',
          ),
        ],
        totalFailures: 12000,
        indexedCount: 0,
      );
      expect(result.failures, hasLength(1));
      expect(result.failureCount, 12000);
    });

    test('ביטול משתמש הוא היחיד שנעצר בלי הודעה להציג', () {
      expect(IndexingStopReason.cancelledByUser.message, isNull);
      for (final reason in [
        IndexingStopReason.blockedTempFallback,
        IndexingStopReason.blockedManualReindexRequired,
        IndexingStopReason.abortedOnWriteFailure,
      ]) {
        expect(reason.message, isNotNull, reason: '$reason חייב הודעה');
        expect(reason.message, isNotEmpty);
      }
    });
  });
}
