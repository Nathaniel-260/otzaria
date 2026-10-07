import 'dart:io';

import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/empty_library/services/library_package/library_package.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_extractor.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/empty_library/services/library_space_estimate.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:path/path.dart' as p;

/// שחרור מנוע החיפוש לפני החלפת תיקיית האינדקס, ופתיחתו מחדש אחריה.
class LibraryIndexHost {
  const LibraryIndexHost({required this.release, required this.reopen});

  final Future<void> Function() release;
  final Future<void> Function() reopen;

  static LibraryIndexHost tantivy() => LibraryIndexHost(
    release: () async {
      final engine = TantivyDataProvider.instance;
      engine.isIndexing.value = false;
      await engine.dispose();
    },
    reopen: () => TantivyDataProvider.instance.reopenIndex(force: true),
  );
}

/// מה שנפרס ל-staging ועוד לא הועבר למקומו.
class StagedLibraryPackage {
  const StagedLibraryPackage({
    required this.stagingRoots,
    required this.booksDir,
    this.indexDir,
  });

  /// תיקיות ה-staging למחיקה בסיום, הצלחה או כשל.
  final List<String> stagingRoots;
  final String booksDir;
  final String? indexDir;
}

/// מקום פנוי שאינו מספיק לפריסה, לכל מיקום שחסר בו.
class InsufficientSpaceException implements Exception {
  const InsufficientSpaceException(this.shortfalls);

  final List<VolumeSpaceNeed> shortfalls;

  @override
  String toString() =>
      'אין מספיק מקום פנוי לפריסת הספרייה.\n'
      '${shortfalls.map((n) => n.describe()).join('\n')}';
}

/// פורס את קובצי הספרייה שהמסייע הוריד (ראה [scanLibraryPackages]) לתיקיות
/// staging ליד היעד, ומחליף את תיקיית האינדקס. העברת הספרים ליעד ועדכון
/// ההגדרות נעשים ב-bloc, כמו בשאר מסלולי הייבוא.
class LibraryPackageImporter {
  LibraryPackageImporter({
    PackageExtractionRunner? runner,
    LibraryIndexHost? indexHost,
    Future<DiskSpaceInfo> Function(String path)? diskSpace,
  }) : _runner = runner ?? runPackageExtractionInIsolate,
       _indexHost = indexHost ?? LibraryIndexHost.tantivy(),
       _diskSpace = diskSpace ?? getDiskSpaceInfo;

  final PackageExtractionRunner _runner;
  final LibraryIndexHost _indexHost;
  final Future<DiskSpaceInfo> Function(String path) _diskSpace;

  /// היכן יישב האינדקס: באנדרואיד תמיד באחסון הפנימי (Tantivy נועל ב-flock,
  /// ש-FUSE של כרטיס SD אינו תומך בו); אחרת ליד תיקיית הספרים.
  static Future<String> indexTargetFor(String booksTarget) async =>
      Platform.isAndroid
      ? AppPaths.androidInternalIndexPath()
      : p.join(AppPaths.libraryRootOf(booksTarget), 'index');

  /// אותו שם כמו `EmptyLibraryBloc.stagingDirFor`, שהעלייה מנקה כשנשאר.
  static String stagingRootFor(String booksTarget) => '$booksTarget.import';

  /// שורש ה-staging של האינדקס — חייב להיות על אותו כונן כמו היעד.
  static String indexStagingRootFor(String booksTarget, String indexTarget) =>
      p.equals(p.dirname(indexTarget), p.dirname(booksTarget))
      ? stagingRootFor(booksTarget)
      : '$indexTarget.import';

  /// זורק [InsufficientSpaceException] כשהמקום הפנוי ידוע ואינו מספיק.
  /// ה-staging יושב ליד כל יעד ומועבר אליו בשינוי שם, ולכן כל כונן צריך
  /// רק את הגודל אחרי החילוץ; האינדקס באנדרואיד נבדק באחסון הפנימי.
  Future<void> checkSpace(
    LibraryPackageSet packages,
    String booksTarget,
    String? indexTarget,
  ) async {
    final index = packages.index;
    final libraryNeed = await _extractedSize(
      packages.folder,
      packages.library,
      ExpansionFallback.database,
    );
    final books = await _diskSpace(booksTarget);
    final needs = [
      VolumeSpaceNeed(
        label: 'הספרייה',
        volumeId: comparableVolumeId(
          booksTarget,
          books.volumeId,
          isAndroid: Platform.isAndroid,
        ),
        requiredBytes: withSafetyMargin(libraryNeed),
        freeBytes: books.freeBytes,
      ),
    ];
    if (index != null && indexTarget != null) {
      final indexNeed = await _extractedSize(
        packages.folder,
        index,
        ExpansionFallback.searchIndex,
      );
      final indexSpace = await _diskSpace(indexTarget);
      needs.add(
        VolumeSpaceNeed(
          label: Platform.isAndroid
              ? 'אינדקס החיפוש (אחסון פנימי)'
              : 'אינדקס החיפוש',
          volumeId: comparableVolumeId(
            indexTarget,
            indexSpace.volumeId,
            isAndroid: Platform.isAndroid,
          ),
          requiredBytes: withSafetyMargin(indexNeed),
          freeBytes: indexSpace.freeBytes,
        ),
      );
    }
    final shortfalls = spaceShortfalls(needs);
    if (shortfalls.isNotEmpty) throw InsufficientSpaceException(shortfalls);
  }

  /// הגודל אחרי חילוץ מכותרת ה-frame שבתחילת החלק הראשון; אומדן כשאינה קריאה.
  static Future<int> _extractedSize(
    PackageFolder folder,
    LibraryPackage package,
    double fallbackRatio,
  ) async {
    int? contentSize;
    try {
      contentSize = await readZstdFrameContentSize(
        folder.openRead(package.parts.first.entry),
      );
    } on Exception {
      // קריאה שנכשלה תיכשל שוב בפריסה עם הודעה משלה; כאן מספיק האומדן.
    }
    return extractedSizeOf(
      package.compressedSize,
      frameContentSize: contentSize,
      fallbackRatio: fallbackRatio,
    );
  }

  /// פורס ל-staging. בכשל או בביטול ה-staging נמחק והחריגה עולה.
  Future<StagedLibraryPackage> stage({
    required LibraryPackageSet packages,
    required String booksTarget,
    required String? indexTarget,
    required PackageExtractionProgress onProgress,
    required ZstdCancelFlag cancel,
  }) async {
    final libraryRoot = stagingRootFor(booksTarget);
    final indexRoot = packages.index == null || indexTarget == null
        ? null
        : indexStagingRootFor(booksTarget, indexTarget);
    final roots = {libraryRoot, ?indexRoot}.toList();
    for (final root in roots) {
      await _deleteDirectory(root);
      await Directory(root).create(recursive: true);
    }
    final staged = StagedLibraryPackage(
      stagingRoots: roots,
      booksDir: p.join(libraryRoot, LibraryPackageKind.library.rootFolder),
      indexDir: indexRoot == null
          ? null
          : p.join(indexRoot, LibraryPackageKind.searchIndex.rootFolder),
    );
    try {
      await _runner(
        PackageExtractionJob(
          packages: packages,
          libraryDestination: libraryRoot,
          indexDestination: indexRoot,
        ),
        onProgress: onProgress,
        cancel: cancel,
      );
      final indexDir = staged.indexDir;
      if (indexDir != null &&
          !await File(
            p.join(indexDir, AppPaths.prebuiltIndexMarkerFileName),
          ).exists()) {
        throw const FormatException('באינדקס שהורד חסר סמן האינדקס המוכן');
      }
    } catch (_) {
      await discard(staged);
      rethrow;
    }
    return staged;
  }

  /// משחרר את מנוע החיפוש ומחליף את [indexTarget] באינדקס שנפרס. בכשל
  /// האינדקס הקודם חוזר; בהצלחה הוא נשמר עד [commitIndex] או [rollbackIndex].
  /// הקורא חייב לקרוא ל-[reopenIndex] בכל מקרה.
  Future<void> installIndex(
    StagedLibraryPackage staged,
    String indexTarget,
  ) async {
    final indexDir = staged.indexDir;
    if (indexDir == null) return;
    await _indexHost.release();
    final previous = '$indexTarget.replaced';
    await _deleteDirectory(previous);
    final hadPrevious = await Directory(indexTarget).exists();
    if (hadPrevious) await Directory(indexTarget).rename(previous);
    try {
      await Directory(p.dirname(indexTarget)).create(recursive: true);
      await Directory(indexDir).rename(indexTarget);
    } catch (_) {
      if (hadPrevious) await Directory(previous).rename(indexTarget);
      rethrow;
    }
  }

  /// הספרייה הועברה למקומה: האינדקס הקודם כבר אינו נחוץ.
  Future<void> commitIndex(String indexTarget) =>
      _deleteDirectory('$indexTarget.replaced');

  /// הספרייה לא הועברה: האינדקס החדש היה מתאים לספרייה שאינה מותקנת.
  Future<void> rollbackIndex(String indexTarget) async {
    final previous = Directory('$indexTarget.replaced');
    await _deleteDirectory(indexTarget);
    if (await previous.exists()) await previous.rename(indexTarget);
  }

  Future<void> reopenIndex() => _indexHost.reopen();

  Future<void> discard(StagedLibraryPackage staged) async {
    for (final root in staged.stagingRoots) {
      await _deleteDirectory(root);
    }
  }

  static Future<void> _deleteDirectory(String path) async {
    final dir = Directory(path);
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // שארית שלא נמחקה תימחק בייבוא הבא או בעלייה (שורש ה-staging).
    }
  }
}
