import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/indexing/models/indexing_failure.dart';

/// כותב את כשלי האינדוקס לקובץ הלוג המקומי, כדי שתמיכה תוכל לקבל
/// רשימה קונקרטית במקום "החיפוש לא מוצא".
class IndexingFailureReporter {
  /// כמה כשלים לפרט בלוג. מעבר לזה נרשם רק סיכום — ספרייה עם אלפי
  /// כשלים (למשל כונן שנותק) הייתה מנפחת את הלוג לעשרות MB.
  static const int maxDetailedFailures = 200;

  /// רושם דוח כשלים ללוג. אינו זורק — כשל בכתיבת הלוג לא יפיל אינדוקס
  /// שכבר הסתיים.
  static void report(IndexingResult result, {DateTime? timestamp}) {
    if (result.failures.isEmpty && result.stopMessage == null) return;

    try {
      ErrorLogFile.appendText(
        buildReport(result, timestamp: timestamp),
      );
    } catch (e) {
      debugPrint('⚠️ כתיבת דוח כשלי האינדוקס ללוג נכשלה: $e');
    }
  }

  /// בונה את גוף הדוח. טהורה — כדי שאפשר יהיה לבדוק אותה בלי גישה לדיסק.
  @visibleForTesting
  static String buildReport(IndexingResult result, {DateTime? timestamp}) {
    final time = (timestamp ?? DateTime.now()).toIso8601String();
    final buffer = StringBuffer()
      ..writeln('=== דוח אינדוקס $time ===')
      ..writeln('Version: ${ErrorLogFile.appVersion}')
      ..writeln('סיום: ${_reasonLabel(result.reason)}')
      ..writeln('ספרים שאונדקסו: ${result.indexedCount}')
      ..writeln('כשלים: ${result.failureCount}');

    final stopMessage = result.stopMessage;
    if (stopMessage != null) {
      buffer.writeln('סיבת עצירה: $stopMessage');
    }

    for (final entry in countByKind(result.failures).entries) {
      buffer.writeln('  ${_kindLabel(entry.key)}: ${entry.value}');
    }

    final suspectedBugs = result.failures.where((f) => f.isLikelyAppBug).length;
    if (suspectedBugs > 0) {
      buffer.writeln(
        'חשודים כבאג בתוכנה (לא תקלה בקובץ של המשתמש): $suspectedBugs',
      );
    }

    // כשלים החשודים כבאג בתוכנה נכתבים ראשונים ועם stack trace מלא —
    // הם היחידים שניתן לתקן מהלוג, ואסור שייחתכו במגבלת הפירוט.
    final ordered = [
      ...result.failures.where((f) => f.isLikelyAppBug),
      ...result.failures.where((f) => !f.isLikelyAppBug),
    ];
    for (final failure in ordered.take(maxDetailedFailures)) {
      buffer
        ..writeln()
        ..writeln('- ${failure.bookTitle}')
        ..writeln('  סיבה: ${failure.reason}')
        ..writeln('  פתרון: ${failure.suggestion}');
      if (failure.isLikelyAppBug) {
        buffer.writeln('  ** חשוד כבאג בתוכנה **');
      }
      final path = failure.bookPath;
      if (path != null && path.isNotEmpty) {
        buffer.writeln('  נתיב: $path');
      }
      for (final entry in failure.context.entries) {
        buffer.writeln('  ${entry.key}: ${entry.value}');
      }
      buffer.writeln('  שגיאה: ${failure.rawError}');
      final stack = failure.stackTrace;
      // stack trace רק לכשלים שניתן לתקן בקוד — לקובץ פגום של המשתמש
      // הוא רק רעש שמנפח את הלוג.
      if (stack != null && failure.isLikelyAppBug) {
        buffer
          ..writeln('  Stack:')
          ..writeln(_indentStack(stack));
      }
    }

    final omitted = result.failureCount - maxDetailedFailures;
    if (omitted > 0) {
      buffer
        ..writeln()
        ..writeln('(עוד $omitted כשלים לא פורטו)');
    }

    buffer.writeln();
    return buffer.toString();
  }

  static String _indentStack(StackTrace stack) => stack
      .toString()
      .trimRight()
      .split('\n')
      .map((line) => '    $line')
      .join('\n');

  /// מספר הכשלים לפי סוג — הבסיס לסיכום שמוצג למשתמש.
  static Map<IndexingFailureKind, int> countByKind(
    List<IndexingFailure> failures,
  ) {
    final counts = <IndexingFailureKind, int>{};
    for (final failure in failures) {
      counts[failure.kind] = (counts[failure.kind] ?? 0) + 1;
    }
    return counts;
  }

  static String _reasonLabel(IndexingStopReason reason) => switch (reason) {
    IndexingStopReason.completed => 'הושלם',
    IndexingStopReason.completedWithFailures => 'הושלם עם כשלים',
    IndexingStopReason.cancelledByUser => 'בוטל על ידי המשתמש',
    IndexingStopReason.blockedTempFallback => 'נחסם — אינדקס זמני',
    IndexingStopReason.blockedManualReindexRequired => 'נחסם — נדרש איפוס ידני',
    IndexingStopReason.abortedOnWriteFailure => 'נעצר — כשל כתיבה',
  };

  static String _kindLabel(IndexingFailureKind kind) => switch (kind) {
    IndexingFailureKind.fileMissing => 'קובץ חסר',
    IndexingFailureKind.pdfOpenFailed => 'PDF שלא נפתח',
    IndexingFailureKind.pdfOpenTimeout => 'PDF שפתיחתו לא הסתיימה בזמן',
    IndexingFailureKind.pdfLoadUnsupported => 'PDF שמנוע ה-PDF לא טוען',
    IndexingFailureKind.pdfTextTimeout => 'PDF שאונדקס חלקית',
    IndexingFailureKind.diskFull => 'דיסק מלא',
    IndexingFailureKind.permissionDenied => 'הרשאות',
    IndexingFailureKind.outOfMemory => 'זיכרון',
    IndexingFailureKind.engineWriteFailed => 'כתיבה למנוע',
    IndexingFailureKind.unknown => 'לא מזוהה',
  };
}
