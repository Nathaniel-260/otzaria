import 'package:equatable/equatable.dart';
import 'package:otzaria/core/messages/library_messages.dart';

/// סוג הכשל באינדוקס ספר — הסיווג נגזר מהחריגה שנתפסה, כדי שהמשתמש
/// יקבל סיבה והנחיה במקום "נכשל" סתמי.
enum IndexingFailureKind {
  /// קובץ הספר לא נמצא בדיסק (נמחק/הועבר אחרי טעינת הספרייה).
  fileMissing,

  /// ה-PDF לא נפתח כלל — קובץ פגום או מוגן בסיסמה.
  pdfOpenFailed,

  /// פתיחת ה-PDF לא הסתיימה בזמן. הספר אינו באינדקס כלל — להבדיל מ-
  /// [pdfTextTimeout], שבו הספר כן נכנס אך חסרים בו עמודים.
  pdfOpenTimeout,

  /// מנוע ה-PDF נכשל בטעינת מבנה המסמך (שגיאת טווח מתוך pdfrx). חוזר על
  /// עצמו בכל ריצה על אותו קובץ — ולכן קבוע, ולא שווה ניסיון נוסף.
  pdfLoadUnsupported,

  /// חלק מעמודי ה-PDF נשמטו בגלל timeout בחילוץ הטקסט. הספר נרשם
  /// כמאונדקס — התוכן שלו חלקי.
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

extension IndexingFailureKindTraits on IndexingFailureKind {
  /// האם ריצה חוזרת יכולה להצליח. כשל קבוע נובע מהקובץ עצמו (מוצפן,
  /// פגום, נמחק) — ריצה חוזרת רק תיכשל שוב ותשאיר את האינדקס "לא מעודכן"
  /// לנצח. כשל זמני (עומס, זיכרון, דיסק, timeout) שווה ניסיון נוסף.
  bool get isPermanent => switch (this) {
    IndexingFailureKind.pdfOpenFailed => true,
    IndexingFailureKind.fileMissing => true,
    IndexingFailureKind.pdfLoadUnsupported => true,
    IndexingFailureKind.pdfOpenTimeout => false,
    IndexingFailureKind.pdfTextTimeout => false,
    IndexingFailureKind.diskFull => false,
    IndexingFailureKind.permissionDenied => false,
    IndexingFailureKind.outOfMemory => false,
    IndexingFailureKind.engineWriteFailed => false,
    IndexingFailureKind.unknown => false,
  };
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
      kind: classify(raw, stackTrace),
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
  ///
  /// [stack] נדרש כדי לזהות מאיזו ספרייה נזרקה השגיאה — ‏`RangeError`
  /// לבדו אינו אומר דבר, ורק המסגרת של pdfrx מסגירה כשל טעינת מסמך.
  ///
  /// ‏[pdfTextTimeout] אינו מסווג כאן: הוא נקבע מפורשות ע"י מדווח העמודים
  /// שנשמטו, כי מנקודת המבט של טקסט השגיאה הוא זהה ל-[pdfOpenTimeout].
  static IndexingFailureKind classify(String rawError, [StackTrace? stack]) {
    final text = rawError.toLowerCase();

    if (text.contains('timeoutexception')) {
      return IndexingFailureKind.pdfOpenTimeout;
    }
    // שגיאת טווח מתוך pdfrx — מבנה המסמך אינו נטען. חייב להיבדק לפני
    // הבדיקות הכלליות, אחרת הוא נופל ל-unknown ומנוסה שוב לנצח.
    if (text.contains('rangeerror') && _isFromPdfrx(stack)) {
      return IndexingFailureKind.pdfLoadUnsupported;
    }

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

  /// האם השגיאה נזרקה מתוך pdfrx. ‏`Future.timeout` אינו סימן מבדיל — הוא
  /// נמצא בשרשרת של כל פתיחה, וסיווג לפיו גורף כל כשל ל-timeout.
  static bool _isFromPdfrx(StackTrace? stack) =>
      stack != null && stack.toString().contains('pdfrx');

  /// כשל שלא ישתנה בריצה חוזרת — הקובץ עצמו אינו ניתן לאינדוקס. ספר כזה
  /// נרשם כמעובד, אחרת כל הפעלה מנסה אותו שוב ומכריזה "האינדקס לא מעודכן".
  bool get isPermanent => kind.isPermanent;

  /// תיאור קצר של הסיבה, בעברית.
  String get reason => switch (kind) {
    IndexingFailureKind.fileMissing => 'הקובץ לא נמצא',
    IndexingFailureKind.pdfOpenFailed => 'קובץ PDF פגום או מוגן בסיסמה',
    IndexingFailureKind.pdfOpenTimeout => 'פתיחת ה-PDF ארכה זמן רב מדי',
    IndexingFailureKind.pdfLoadUnsupported =>
      'מנוע ה-PDF לא הצליח לטעון את הקובץ',
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
    IndexingFailureKind.pdfOpenTimeout =>
      'הספר לא נכנס לאינדקס. הרץ עדכון חוזר במחשב פנוי; אם זה חוזר, הקובץ כבד מדי לעיבוד',
    IndexingFailureKind.pdfLoadUnsupported =>
      'הספר לא ייכנס לאינדקס. שמור את הקובץ מחדש מקורא PDF, או החלף אותו בעותק אחר',
    IndexingFailureKind.pdfTextTimeout =>
      'הספר אונדקס חלקית — חלק מעמודיו לא ייכנסו לחיפוש. עדכון חוזר עשוי להשלים אותו',
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
      LibraryMessages.searchIndexOpenFailed,
    IndexingStopReason.blockedManualReindexRequired =>
      LibraryMessages.indexRequiresManualRebuild,
    IndexingStopReason.abortedOnWriteFailure =>
      LibraryMessages.indexingAbortedOnWriteFailure,
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

  /// מסיר כשלים של ספרים שהצליחו בניסיון חוזר, כדי שלא ידווחו כנכשלים.
  void dropFor(Set<String> bookPaths) {
    if (bookPaths.isEmpty) return;
    final before = _collected.length;
    _collected.removeWhere((f) => bookPaths.contains(f.bookPath));
    _total -= before - _collected.length;
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

  /// ריצה שהסתיימה — עם או בלי כשלים.
  ///
  /// הסיבה נקבעת לפי המונה ולא לפי אורך הרשימה: כשהאיסוף נחתך בתקרה,
  /// רשימה ריקה עם מונה חי הייתה מדווחת "הושלם במלואו" בעוד ספרים חסרים.
  factory IndexingResult.finished({
    required List<IndexingFailure> failures,
    required int indexedCount,
    int? totalFailures,
  }) {
    final count = totalFailures ?? failures.length;
    return IndexingResult(
      reason: count == 0
          ? IndexingStopReason.completed
          : IndexingStopReason.completedWithFailures,
      failures: failures,
      totalFailures: count,
      indexedCount: indexedCount,
    );
  }

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
