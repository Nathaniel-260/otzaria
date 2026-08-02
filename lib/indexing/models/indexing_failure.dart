import 'package:equatable/equatable.dart';

/// סוג הכשל באינדוקס ספר — הסיווג נגזר מהחריגה שנתפסה, כדי שהמשתמש
/// יקבל סיבה והנחיה במקום "נכשל" סתמי.
enum IndexingFailureKind {
  /// קובץ הספר לא נמצא בדיסק (נמחק/הועבר אחרי טעינת הספרייה).
  fileMissing,

  /// ה-PDF לא נפתח כלל — קובץ פגום או מוגן בסיסמה.
  pdfOpenFailed,

  /// חלק מעמודי ה-PDF נשמטו בגלל timeout בחילוץ הטקסט.
  pdfTextTimeout,

  /// אין מקום פנוי בדיסק לכתיבת האינדקס.
  diskFull,

  /// אין הרשאת גישה לקובץ הספר או לתיקיית האינדקס.
  permissionDenied,

  /// אזל הזיכרון בעת עיבוד הספר (בדרך כלל ספר ענק או PDF מצויר).
  outOfMemory,

  /// כשל בכתיבה למנוע החיפוש עצמו (FFI/Tantivy).
  engineWriteFailed,

  /// כשל שלא סווג.
  unknown,
}

/// כשל אינדוקס יחיד — ספר, סיווג, ומספיק הקשר טכני כדי לאתר באג בתוכנה
/// מהלוג בלבד: stack trace ופרטי הספר שגרם לו.
class IndexingFailure extends Equatable {
  final String bookTitle;
  final String? bookPath;
  final IndexingFailureKind kind;
  final String rawError;
  final StackTrace? stackTrace;

  /// פרטי הספר שנחוצים לשחזור התקלה (סוג, מזהה, גודל קובץ).
  final Map<String, String> context;

  const IndexingFailure({
    required this.bookTitle,
    required this.kind,
    required this.rawError,
    this.bookPath,
    this.stackTrace,
    this.context = const {},
  });

  /// יוצר כשל מסווג מתוך חריגה שנתפסה.
  factory IndexingFailure.fromError({
    required String bookTitle,
    String? bookPath,
    required Object error,
    StackTrace? stackTrace,
    Map<String, String> context = const {},
  }) {
    final raw = error.toString();
    return IndexingFailure(
      bookTitle: bookTitle,
      bookPath: bookPath,
      kind: classify(raw),
      rawError: raw,
      stackTrace: stackTrace,
      context: context,
    );
  }

  /// כשל שהסיווג לא זיהה, או כשל בכתיבה למנוע — אלה בדרך כלל באג בתוכנה
  /// ולא תקלה בקובץ של המשתמש. מסומנים בלוג כדי שיטופלו.
  bool get isLikelyAppBug =>
      kind == IndexingFailureKind.unknown ||
      kind == IndexingFailureKind.engineWriteFailed;

  /// מסווג טקסט שגיאה לסוג כשל. הבדיקות מסודרות מהספציפי לכללי — הודעת
  /// שגיאה יכולה להכיל כמה סימנים, והראשון שמתאים הוא המדויק יותר.
  static IndexingFailureKind classify(String rawError) {
    final text = rawError.toLowerCase();

    if (text.contains('no space left') ||
        text.contains('disk full') ||
        text.contains('there is not enough space')) {
      return IndexingFailureKind.diskFull;
    }
    if (text.contains('out of memory') ||
        text.contains('oom') ||
        text.contains('cannot allocate')) {
      return IndexingFailureKind.outOfMemory;
    }
    if (text.contains('access is denied') ||
        text.contains('permission denied') ||
        text.contains('operation not permitted')) {
      return IndexingFailureKind.permissionDenied;
    }
    if (text.contains('no such file') ||
        text.contains('cannot find the file') ||
        text.contains('filesystemexception: cannot open file')) {
      return IndexingFailureKind.fileMissing;
    }
    if (text.contains('timeoutexception')) {
      return IndexingFailureKind.pdfTextTimeout;
    }
    if (text.contains('password') ||
        text.contains('pdfexception') ||
        text.contains('failed to load pdf') ||
        text.contains('pdfdocument')) {
      return IndexingFailureKind.pdfOpenFailed;
    }
    if (text.contains('panicexception') ||
        text.contains('tantivy') ||
        text.contains('schemaerror')) {
      return IndexingFailureKind.engineWriteFailed;
    }
    return IndexingFailureKind.unknown;
  }

  /// תיאור קצר של הסיבה, בעברית.
  String get reason => switch (kind) {
    IndexingFailureKind.fileMissing => 'הקובץ לא נמצא',
    IndexingFailureKind.pdfOpenFailed => 'קובץ PDF פגום או מוגן בסיסמה',
    IndexingFailureKind.pdfTextTimeout => 'חילוץ הטקסט מה-PDF ארך זמן רב מדי',
    IndexingFailureKind.diskFull => 'אין מקום פנוי בדיסק',
    IndexingFailureKind.permissionDenied => 'אין הרשאת גישה לקובץ',
    IndexingFailureKind.outOfMemory => 'אזל הזיכרון בעת עיבוד הספר',
    IndexingFailureKind.engineWriteFailed => 'כשל בכתיבה למנוע החיפוש',
    IndexingFailureKind.unknown => 'שגיאה לא מזוהה',
  };

  /// מה המשתמש יכול לעשות בפועל.
  String get suggestion => switch (kind) {
    IndexingFailureKind.fileMissing =>
      'רענן את הספרייה — ייתכן שהקובץ נמחק או הועבר',
    IndexingFailureKind.pdfOpenFailed =>
      'החלף את הקובץ בעותק תקין, או הסר אותו מהספרייה',
    IndexingFailureKind.pdfTextTimeout =>
      'הספר אונדקס חלקית; אינדוקס חוזר במחשב פנוי עשוי להשלים אותו',
    IndexingFailureKind.diskFull => 'פנה מקום בכונן והרץ את העדכון שוב',
    IndexingFailureKind.permissionDenied =>
      'ודא שלתוכנה יש הרשאת גישה לקובץ ולתיקיית האינדקס',
    IndexingFailureKind.outOfMemory => 'סגור תוכנות אחרות והרץ את העדכון שוב',
    IndexingFailureKind.engineWriteFailed =>
      'אפס את האינדקס מההגדרות ובנה אותו מחדש',
    IndexingFailureKind.unknown =>
      'שלח את קובץ הלוג לתמיכה דרך "דיווח על תקלה"',
  };

  @override
  List<Object?> get props => [bookTitle, bookPath, kind, rawError, context];
}

/// כיצד הסתיימה ריצת אינדוקס. מחליף את ה-bool שאיחד "בוטל על ידי
/// המשתמש" עם "נחסם" ועם "נעצר בכשל" — שלושתם הוצגו כ"האינדקס לא מעודכן".
enum IndexingStopReason {
  /// הסתיים לגמרי, בלי כשלים.
  completed,

  /// הסתיים, אך חלק מהספרים נכשלו ואינם באינדקס.
  completedWithFailures,

  /// המשתמש לחץ "עצור".
  cancelledByUser,

  /// המנוע רץ על אינדקס זמני — כתיבה הייתה אובדת.
  blockedTempFallback,

  /// האינדקס אינו תואם למנוע ודורש איפוס ידני.
  blockedManualReindexRequired,

  /// נעצר באמצע כי לא ניתן היה לנקות כתיבה חלקית של ספר.
  abortedOnWriteFailure,
}

extension IndexingStopReasonMessage on IndexingStopReason {
  /// הודעה למשתמש על סיבת העצירה; null כשאין מה להסביר — ריצה שהסתיימה,
  /// או ביטול יזום של המשתמש.
  String? get message => switch (this) {
    IndexingStopReason.completed => null,
    IndexingStopReason.completedWithFailures => null,
    IndexingStopReason.cancelledByUser => null,
    IndexingStopReason.blockedTempFallback =>
      'פתיחת אינדקס החיפוש נכשלה — האינדוקס הושהה. נסה להפעיל מחדש את התוכנה',
    IndexingStopReason.blockedManualReindexRequired =>
      'האינדקס אינו תואם לגרסת החיפוש הנוכחית. יש לאפס ולבנות אותו מחדש',
    IndexingStopReason.abortedOnWriteFailure =>
      'האינדוקס נעצר בגלל כשל בכתיבה לאינדקס. הפעל מחדש את התוכנה ונסה שוב',
  };
}

/// אוסף כשלים בתקרה. כשל המוני (כונן שנותק באמצע אינדוקס של עשרות
/// אלפי ספרים) היה מצבֵּר עשרות אלפי אובייקטים עם stack traces — מאות MB.
/// המונה נשאר מדויק; רק הפירוט נחתך.
class IndexingFailureCollector {
  /// כמה כשלים לשמור במלואם. מעבר לזה רק המונה גדל — הפירוט כבר חוזר
  /// על עצמו ממילא, כי כשל המוני הוא תמיד אותה סיבה.
  static const int maxCollected = 500;

  final List<IndexingFailure> _collected = [];
  int _total = 0;

  int get total => _total;
  List<IndexingFailure> get collected => List.unmodifiable(_collected);
  bool get isEmpty => _total == 0;

  void add(IndexingFailure failure) {
    _total++;
    if (_collected.length < maxCollected) {
      _collected.add(failure);
    }
  }
}

/// תוצאת ריצת אינדוקס: כיצד הסתיימה, ומה נכשל בדרך.
class IndexingResult extends Equatable {
  final IndexingStopReason reason;

  /// הכשלים שנשמרו במלואם — עד [IndexingFailureCollector.maxCollected].
  final List<IndexingFailure> failures;

  /// מספר הכשלים בפועל; גדול מ-[failures] כשהאיסוף נחתך.
  final int totalFailures;

  final int indexedCount;

  const IndexingResult({
    required this.reason,
    this.failures = const [],
    this.indexedCount = 0,
    int? totalFailures,
  }) : totalFailures = totalFailures ?? -1;

  /// ריצה שהסתיימה — עם או בלי כשלים, לפי מה שנאסף.
  factory IndexingResult.finished({
    required List<IndexingFailure> failures,
    required int indexedCount,
    int? totalFailures,
  }) => IndexingResult(
    reason: failures.isEmpty
        ? IndexingStopReason.completed
        : IndexingStopReason.completedWithFailures,
    failures: failures,
    totalFailures: totalFailures ?? failures.length,
    indexedCount: indexedCount,
  );

  /// ריצה שנעצרה לפני סיומה.
  factory IndexingResult.stopped(
    IndexingStopReason reason, {
    List<IndexingFailure> failures = const [],
    int indexedCount = 0,
    int? totalFailures,
  }) => IndexingResult(
    reason: reason,
    failures: failures,
    totalFailures: totalFailures ?? failures.length,
    indexedCount: indexedCount,
  );

  /// מספר הכשלים להצגה — נופל לאורך הרשימה כשלא נמסר מונה.
  int get failureCount => totalFailures < 0 ? failures.length : totalFailures;

  /// האם כל הספרים שניתן היה לאנדקס אכן אונדקסו.
  bool get isFullyComplete => reason == IndexingStopReason.completed;

  /// האם הריצה הגיעה לסופה (גם אם ספרים בודדים נכשלו) — הבחנה זו קובעת
  /// אם להריץ commit ולסמן את העבודה כגמורה.
  bool get didFinish =>
      reason == IndexingStopReason.completed ||
      reason == IndexingStopReason.completedWithFailures;

  /// הודעה למשתמש על סיבת העצירה; null כשהריצה הסתיימה כרגיל.
  String? get stopMessage => reason.message;

  @override
  List<Object?> get props => [reason, failures, totalFailures, indexedCount];
}
