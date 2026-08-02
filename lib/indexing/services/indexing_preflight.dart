import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:path/path.dart' as p;

/// תקלה שנמצאה בבדיקה המקדימה לאינדוקס.
enum IndexingPreflightIssue {
  /// לא ניתן לכתוב לתיקיית האינדקס (הרשאות, נעילה, או דיסק מלא).
  indexPathNotWritable,

  /// תיקיית האינדקס על כונן רשת — נעילות הקבצים של מנוע החיפוש
  /// אינן אמינות שם, והאינדוקס נוטה להיכשל באמצע.
  indexPathOnNetworkDrive,

  /// תיקיית האינדקס בתוך תיקיית סנכרון ענן — הסנכרון נועל קבצים
  /// תחת המנוע ומשחית את האינדקס.
  indexPathInCloudSyncFolder,

  /// נשאר סנטינל מריצה קודמת: פתיחת המנוע קרסה בפעם הקודמת.
  previousOpenCrashed,

  /// המנוע רץ כרגע על אינדקס זמני — כל כתיבה תיזרק בהפעלה הבאה.
  engineOnTempIndex,
}

/// תוצאת בדיקה מקדימה: התקלה, האם היא חוסמת, וההסבר למשתמש.
@immutable
class IndexingPreflightFinding {
  final IndexingPreflightIssue issue;
  final String? detail;

  const IndexingPreflightFinding(this.issue, {this.detail});

  /// האם התקלה מונעת אינדוקס תקין (להבדיל מאזהרה שכדאי להציג).
  bool get isBlocking =>
      issue == IndexingPreflightIssue.indexPathNotWritable ||
      issue == IndexingPreflightIssue.engineOnTempIndex;

  String get title => switch (issue) {
    IndexingPreflightIssue.indexPathNotWritable =>
      'לא ניתן לכתוב לתיקיית האינדקס',
    IndexingPreflightIssue.indexPathOnNetworkDrive =>
      'תיקיית האינדקס על כונן רשת',
    IndexingPreflightIssue.indexPathInCloudSyncFolder =>
      'תיקיית האינדקס בתוך תיקיית סנכרון ענן',
    IndexingPreflightIssue.previousOpenCrashed =>
      'פתיחת האינדקס קרסה בהפעלה הקודמת',
    IndexingPreflightIssue.engineOnTempIndex => 'מנוע החיפוש רץ על אינדקס זמני',
  };

  String get suggestion => switch (issue) {
    IndexingPreflightIssue.indexPathNotWritable =>
      'ודא שיש מקום פנוי בכונן ושלתוכנה יש הרשאת כתיבה, או בחר מיקום אינדקס אחר בהגדרות',
    IndexingPreflightIssue.indexPathOnNetworkDrive =>
      'העבר את האינדקס לכונן מקומי — אינדוקס על כונן רשת נוטה להיכשל באמצע',
    IndexingPreflightIssue.indexPathInCloudSyncFolder =>
      'העבר את האינדקס לתיקייה שאינה מסונכרנת, או השהה את הסנכרון בזמן האינדוקס',
    IndexingPreflightIssue.previousOpenCrashed =>
      'אם זה יקרה שוב, האינדקס יוזז הצידה ותיבנה גרסה חדשה',
    IndexingPreflightIssue.engineOnTempIndex =>
      'הפעל מחדש את התוכנה. אם התקלה חוזרת, אפס את האינדקס מההגדרות',
  };
}

/// בדיקה מקדימה לפני אינדוקס — תופסת את הכשלים הסביבתיים הניתנים לחיזוי,
/// לפני שהמשתמש מבזבז שעה על ריצה שתיכשל.
///
/// אינה מכסה כשלים פר-קובץ (PDF פגום, timeout) — אלה מסווגים בזמן הריצה.
class IndexingPreflight {
  /// שמות תיקיות סנכרון ענן נפוצות. ההשוואה על רכיב נתיב שלם, כדי
  /// שספרייה בשם "Dropbox של הרב" לא תסומן בטעות.
  static const Set<String> _cloudFolderNames = {
    'onedrive',
    'dropbox',
    'google drive',
    'googledrive',
    'icloud drive',
    'yandexdisk',
  };

  /// בודקת את נתיב האינדקס בלבד — טהורה, בלי גישה לדיסק.
  @visibleForTesting
  static List<IndexingPreflightFinding> inspectPath(String indexPath) {
    final findings = <IndexingPreflightFinding>[];

    if (indexPath.startsWith(r'\\') || indexPath.startsWith('//')) {
      findings.add(
        IndexingPreflightFinding(
          IndexingPreflightIssue.indexPathOnNetworkDrive,
          detail: indexPath,
        ),
      );
    }

    final segments = p.split(indexPath).map((s) => s.toLowerCase());
    for (final segment in segments) {
      // OneDrive מותקן גם כ-"OneDrive - שם ארגון"; התחילית מזהה את שניהם.
      final isCloud = _cloudFolderNames.any(
        (name) => segment == name || segment.startsWith('$name -'),
      );
      if (isCloud) {
        findings.add(
          IndexingPreflightFinding(
            IndexingPreflightIssue.indexPathInCloudSyncFolder,
            detail: indexPath,
          ),
        );
        break;
      }
    }

    return findings;
  }

  /// מריצה את כל הבדיקות המקדימות ומחזירה את התקלות שנמצאו.
  ///
  /// [isTempFallback] — האם המנוע כבר נפל לאינדקס זמני.
  static Future<List<IndexingPreflightFinding>> run({
    required bool isTempFallback,
  }) async {
    final findings = <IndexingPreflightFinding>[];

    if (isTempFallback) {
      findings.add(
        const IndexingPreflightFinding(
          IndexingPreflightIssue.engineOnTempIndex,
        ),
      );
    }

    String indexPath;
    try {
      indexPath = await AppPaths.getIndexPath();
    } catch (e) {
      debugPrint('⚠️ preflight: פענוח נתיב האינדקס נכשל: $e');
      return findings;
    }

    findings.addAll(inspectPath(indexPath));

    final sentinel = File(
      p.join(Directory(indexPath).parent.path, '.engine_init_started'),
    );
    if (sentinel.existsSync()) {
      findings.add(
        const IndexingPreflightFinding(
          IndexingPreflightIssue.previousOpenCrashed,
        ),
      );
    }

    if (!await _canWriteTo(indexPath)) {
      findings.add(
        IndexingPreflightFinding(
          IndexingPreflightIssue.indexPathNotWritable,
          detail: indexPath,
        ),
      );
    }

    return findings;
  }

  /// כתיבת קובץ בדיקה זעיר — תופסת גם חוסר הרשאות וגם דיסק מלא, בלי
  /// לתלות את הבדיקה ב-API של מקום פנוי (שאינו זמין בכל הפלטפורמות).
  static Future<bool> _canWriteTo(String dirPath) async {
    final probe = File(p.join(dirPath, '.otzaria_write_probe'));
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      await probe.writeAsString('ok', flush: true);
      return true;
    } catch (e) {
      debugPrint('⚠️ preflight: כתיבת בדיקה ל-$dirPath נכשלה: $e');
      return false;
    } finally {
      try {
        if (probe.existsSync()) probe.deleteSync();
      } catch (_) {}
    }
  }
}
