import 'package:equatable/equatable.dart';
import 'package:otzaria/empty_library/services/library_package/library_package.dart';

abstract class EmptyLibraryEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

/// שימוש בספרייה קיימת במקומה: [folderPath] נשמר כנתיב הספרייה כמות שהוא,
/// ללא העתקה או חילוץ. חוסך שכפול של קובץ ה-DB כשהוא כבר יושב במקום מתאים.
class UseLibraryInPlaceRequested extends EmptyLibraryEvent {
  final String folderPath;

  UseLibraryInPlaceRequested(this.folderPath);

  @override
  List<Object?> get props => [folderPath];
}

class DownloadLibraryRequested extends EmptyLibraryEvent {
  /// מיקום היעד שאליו תורד הספרייה. null → נתיב ברירת המחדל של האפליקציה.
  final String? targetPath;

  DownloadLibraryRequested({this.targetPath});

  @override
  List<Object?> get props => [targetPath];
}

/// עדכון ספרייה קיימת (מההגדרות) עם גיבוי בטוח של ה-DB הישן.
/// ה-DB הישן ב-[existingLibraryPath] מגובה, ונמחק לצמיתות רק בהצלחה (ומשוחזר
/// בכישלון). [isDownload] → הורדה מחדש; אחרת [sourceFolder] הוא תיקייה עם
/// seforim.db.
class UpdateLibraryRequested extends EmptyLibraryEvent {
  final bool isDownload;
  final String? sourceFolder;
  final String targetPath;
  final String existingLibraryPath;

  UpdateLibraryRequested({
    required this.isDownload,
    this.sourceFolder,
    required this.targetPath,
    required this.existingLibraryPath,
  });

  @override
  List<Object?> get props => [
    isDownload,
    sourceFolder,
    targetPath,
    existingLibraryPath,
  ];
}

/// ייבוא ספרייה מתיקייה שנבחרה: מזהה אוטומטית את נכסי הספרייה שבתוכה (seforim.db,
/// קטלוג, מילון, תלמוד בבלי) בגרסה דחוסה או רגילה, ומחלץ/מעתיק כל אחד אל היעד.
/// [backupExistingPath] — כשמסופק (עדכון במקום), ה-DB הישן בנתיב זה מגובה
/// ומשוחזר בכישלון.
class ImportLibraryFolderRequested extends EmptyLibraryEvent {
  final String sourceFolder;
  final String targetPath;
  final String? backupExistingPath;

  ImportLibraryFolderRequested({
    required this.sourceFolder,
    required this.targetPath,
    this.backupExistingPath,
  });

  @override
  List<Object?> get props => [sourceFolder, targetPath, backupExistingPath];
}

/// ייבוא ספרייה מארכיון ZIP או ZST אל תיקיית היעד. [backupExistingPath]
/// משמש להחזרת ה-DB הישן אם החילוץ או אימות הארכיון נכשלים.
class ImportLibraryArchiveRequested extends EmptyLibraryEvent {
  final String archivePath;
  final String targetPath;
  final String? backupExistingPath;

  ImportLibraryArchiveRequested({
    required this.archivePath,
    required this.targetPath,
    this.backupExistingPath,
  });

  @override
  List<Object?> get props => [archivePath, targetPath, backupExistingPath];
}

/// ייבוא קובצי הספרייה שמסייע ההורדה הכין (חלקי tar.zst, ואופציונלית
/// אינדקס מוכן) אל [targetPath]. [backupExistingPath] — כמו בייבוא תיקייה.
class ImportLibraryPackageRequested extends EmptyLibraryEvent {
  final LibraryPackageSet packages;
  final String targetPath;
  final String? backupExistingPath;

  ImportLibraryPackageRequested({
    required this.packages,
    required this.targetPath,
    this.backupExistingPath,
  });

  @override
  List<Object?> get props => [packages, targetPath, backupExistingPath];
}

/// עוצר פריסה של [ImportLibraryPackageRequested] לפני שהספרייה מוחלפת.
class CancelLibraryImportRequested extends EmptyLibraryEvent {}

/// בודק מקום פנוי בהתקנה וקובע אם כפתור ההורדה זמין.
/// נשלח בעת טעינת המסך.
class CheckDiskSpaceRequested extends EmptyLibraryEvent {}

/// בחירת מיקום אחסון הספרייה ב-Android (אחסון פנימי או כרטיס SD).
/// [libraryRoot] ריק/null => אחסון פנימי. הבחירה נשמרת ובדיקת המקום הפנוי
/// מורצת מחדש עבור היעד החדש.
class StorageLocationSelected extends EmptyLibraryEvent {
  final String? libraryRoot;

  StorageLocationSelected(this.libraryRoot);

  @override
  List<Object?> get props => [libraryRoot];
}
