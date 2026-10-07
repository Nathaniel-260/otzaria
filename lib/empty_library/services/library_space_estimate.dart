import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/utils/text/byte_size_text.dart';
import 'package:path/path.dart' as p;

/// גודל הקובץ המרבי ב-FAT32: 4GiB פחות בייט.
const int fat32MaxFileBytes = 0xFFFFFFFF;

/// יחסי התפיחה למקרה שגודל התוכן אינו רשום בכותרת ה-frame. נמדדו על
/// הגרסאות הנוכחיות ועוגלו כלפי מעלה; כולם נבדקים מול [measuredLibraryDownload].
abstract final class ExpansionFallback {
  /// seforim.db: נמדד 2.07 (1.807GB ← 3.739GB). גם ארכיון הספרייה של המסייע.
  static const double database = 2.5;

  /// אינדקס החיפוש המוכן: נמדד 1.40 (1.725GB ← 2.413GB).
  static const double searchIndex = 1.6;

  /// קטלוג אוצר הספרים: נמדד 6.3 (6MB ← 37.6MB).
  static const double catalog = 8;

  /// ארכיון PDF (תלמוד בבלי): כמעט אינו נדחס, נמדד 1.003.
  static const double pdfArchive = 1.1;
}

/// גודל דחוס וגודל אחרי חילוץ של נכס אחד.
typedef ArchiveSize = ({int compressed, int extracted});

/// seforim.db כפי שנמדד בגרסה הנוכחית — הקובץ הגדול בספרייה.
const int measuredDatabaseBytes = 3738877952;

/// הנכסים של הורדה ראשונית בגדלים שנמדדו (DB, תלמוד, קטלוג, מילון), לבדיקת
/// הסף לפני שהגדלים האמיתיים ידועים.
const List<ArchiveSize> measuredLibraryDownload = [
  (compressed: 1807000000, extracted: measuredDatabaseBytes),
  (compressed: 472000000, extracted: 473500000),
  (compressed: 6000000, extracted: 37600000),
  (compressed: 57000000, extracted: 57000000),
];

/// אורך כותרת frame מרבי: magic, descriptor, window, dictionary id, content size.
const int zstdFrameHeaderMaxBytes = 18;

/// `Frame_Content_Size` מכותרת ה-frame הראשון, או null כשאינו רשום
/// (דחיסה מצינור) או כשהבייטים אינם frame של zstd.
int? zstdFrameContentSize(List<int> header) {
  if (header.length < 5 ||
      header[0] != 0x28 ||
      header[1] != 0xB5 ||
      header[2] != 0x2F ||
      header[3] != 0xFD) {
    return null;
  }
  final descriptor = header[4];
  final fcsFlag = descriptor >> 6;
  final singleSegment = (descriptor >> 5) & 1 == 1;
  const dictionaryIdBytes = [0, 1, 2, 4];
  final fcsBytes = switch (fcsFlag) {
    0 => singleSegment ? 1 : 0,
    1 => 2,
    2 => 4,
    _ => 8,
  };
  if (fcsBytes == 0) return null;
  final offset =
      5 + (singleSegment ? 0 : 1) + dictionaryIdBytes[descriptor & 3];
  if (header.length < offset + fcsBytes) return null;
  var value = 0;
  for (var i = fcsBytes - 1; i >= 0; i--) {
    value = (value << 8) | header[offset + i];
  }
  // בשדה של שני בייטים הערך מוסט ב-256 לפי התקן.
  return fcsBytes == 2 ? value + 256 : value;
}

/// קורא רק את תחילת [stream] (קובץ, SAF או HTTP) ומפענח את גודל התוכן.
Future<int?> readZstdFrameContentSize(Stream<List<int>> stream) async {
  final header = <int>[];
  await for (final chunk in stream) {
    header.addAll(chunk);
    if (header.length >= zstdFrameHeaderMaxBytes) break;
  }
  return zstdFrameContentSize(header);
}

/// הגודל אחרי חילוץ: מהכותרת כשהיא אמינה, אחרת לפי [fallbackRatio].
/// כותרת קטנה מהדחוס מעידה על כמה frames, והראשון אינו מייצג את כולם.
int extractedSizeOf(
  int compressedSize, {
  int? frameContentSize,
  required double fallbackRatio,
}) {
  if (frameContentSize != null && frameContentSize >= compressedSize) {
    return frameContentSize;
  }
  return (compressedSize * fallbackRatio).ceil();
}

/// מרווח ביטחון: 5% ולא פחות מ-256MiB (מטא-דאטה של מערכת הקבצים, WAL).
int withSafetyMargin(int bytes) =>
    bytes <= 0 ? 0 : bytes + math.max(256 << 20, bytes ~/ 20);

/// השיא שהחילוץ מוסיף כשהארכיונים נמחקים בזה אחר זה: לפני נכס i כבר
/// חולצו הקודמים וקבציהם הדחוסים נמחקו, והדחוס של i עוד קיים.
int peakExtractionGrowth(List<ArchiveSize> items) {
  var peak = 0;
  var growth = 0;
  for (final item in items) {
    peak = math.max(peak, growth + item.extracted);
    growth += item.extracted - item.compressed;
  }
  return peak;
}

/// דרישת מקום של מיקום אחד. [volumeId] null — לא ידוע אם חולק כונן.
class VolumeSpaceNeed {
  const VolumeSpaceNeed({
    required this.label,
    required this.volumeId,
    required this.requiredBytes,
    required this.freeBytes,
  });

  final String label;
  final String? volumeId;
  final int requiredBytes;

  /// -1 כשלא ניתן לקבוע; אז המיקום אינו נחסם.
  final int freeBytes;

  bool get isShort => freeBytes >= 0 && freeBytes < requiredBytes;

  String describe() =>
      '$label: נדרש ${formatMegabytesLtr(requiredBytes, fractionDigits: 0)}, '
      'פנוי ${formatMegabytesLtr(freeBytes, fractionDigits: 0)}.';
}

/// מאחד דרישות של מיקומים על אותו כונן ומחזיר את אלה שאין בהם די מקום.
List<VolumeSpaceNeed> spaceShortfalls(List<VolumeSpaceNeed> needs) {
  final merged = <VolumeSpaceNeed>[];
  for (final need in needs.where((n) => n.requiredBytes > 0)) {
    final index = need.volumeId == null
        ? -1
        : merged.indexWhere((m) => m.volumeId == need.volumeId);
    if (index < 0) {
      merged.add(need);
      continue;
    }
    final existing = merged[index];
    merged[index] = VolumeSpaceNeed(
      label: '${existing.label} + ${need.label} (אותו כונן)',
      volumeId: existing.volumeId,
      requiredBytes: existing.requiredBytes + need.requiredBytes,
      freeBytes: existing.freeBytes,
    );
  }
  return merged.where((n) => n.isShort).toList();
}

/// הודעה לכל מיקום שחסר בו מקום, או null כשהכול מספיק.
String? insufficientSpaceMessage(List<VolumeSpaceNeed> needs) {
  final shortfalls = spaceShortfalls(needs);
  if (shortfalls.isEmpty) return null;
  return 'אין מספיק מקום פנוי.\n'
      '${shortfalls.map((n) => n.describe()).join('\n')}\n'
      'יש לפנות מקום ולנסות שוב.';
}

/// FAT32 חוסם רק קובץ יחיד מעל 4GiB-1. גודל לא ידוע אינו חוסם — הכתיבה
/// עצמה תיכשל אם הוא בכל זאת גדול מדי.
bool exceedsFat32FileLimit(int? largestFileBytes) =>
    largestFileBytes != null && largestFileBytes > fat32MaxFileBytes;

/// כרך בלי תמיכה בקבצים גדולים (FAT32) נחסם רק כשהקובץ הגדול חורג.
bool volumeCanHoldLibrary({
  required bool supportsLargeFiles,
  required int? largestFileBytes,
}) => supportsLargeFiles || !exceedsFat32FileLimit(largestFileBytes);

/// גודל seforim.db שבתיקיית הספרים, או [measuredDatabaseBytes] כשאינו קיים.
Future<int> installedDatabaseBytes(String booksPath) async {
  if (booksPath.isEmpty) return measuredDatabaseBytes;
  final db = File(p.join(booksPath, DatabaseConstants.databaseFileName));
  try {
    return await db.length();
  } on FileSystemException {
    return measuredDatabaseBytes;
  }
}

final _androidInternalPath = RegExp(
  r'^/(data|storage/emulated|storage/self|sdcard)(/|$)',
);

/// מזהה כונן להשוואה. באנדרואיד `/data` ו-`/storage/emulated` הם אותו אחסון
/// פנימי, אך df מדווח עליהם מערכות קבצים שונות (FUSE מעל `/data/media`).
String? comparableVolumeId(
  String path,
  String? volumeId, {
  required bool isAndroid,
}) {
  if (volumeId == null || !isAndroid) return volumeId;
  return _androidInternalPath.hasMatch(path) ? 'android-internal' : volumeId;
}
