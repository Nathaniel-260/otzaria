import 'dart:convert';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/services/library_package/library_package.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show SplitAsset, kSplitManifestSuffix;

/// רכיבי הספרייה שהייבוא מזהה ומדווח עליהם.
enum LibraryComponent { libraryDb, talmudBavli, catalog, lexicon, searchIndex }

/// מה הייבוא התקין, ואילו רכיבים חסרים בספרייה אחריו.
class LibraryImportReport extends Equatable {
  const LibraryImportReport({required this.imported, required this.missing});

  final Set<LibraryComponent> imported;
  final Set<LibraryComponent> missing;

  @override
  List<Object?> get props => [imported, missing];
}

/// תת-התיקייה שבה חבילת אנדרואיד המלאה מניחה את קובצי הספרייה.
const kLibraryDbSubfolder = 'library_db';

enum RawAssetFormat {
  /// zstd שמפוענח לקובץ — קובץ אחד או חלקים לפי מניפסט.
  zstd,

  /// קובץ מוכן שמועתק כמות שהוא.
  plain,

  /// tar.zst שנפרס לתיקייה.
  tarZstd,

  /// תיקייה שכבר חולצה; נתמכת רק בתיקייה רגילה (לא SAF).
  directory,
}

/// נכס ספרייה גולמי שנמצא בתיקיית המקור.
class RawLibraryAsset {
  const RawLibraryAsset({
    required this.component,
    required this.format,
    required this.folder,
    required this.sourceName,
    this.parts = const [],
    this.sha256,
    this.directoryPath,
  });

  final LibraryComponent component;
  final RawAssetFormat format;

  /// התיקייה שבה יושבים [parts] — השורש או [kLibraryDbSubfolder].
  final PackageFolder folder;

  /// שם הקובץ במקור, או שם הארכיון השלם כשהוא מפוצל.
  final String sourceName;
  final List<LibraryPackagePart> parts;

  /// ה-SHA-256 של הארכיון השלם, ממניפסט החלקים.
  final String? sha256;
  final String? directoryPath;

  int get size => parts.fold(0, (sum, part) => sum + part.size);

  /// שם הקובץ או התיקייה בתיקיית הספרים.
  String get targetName => switch (component) {
    LibraryComponent.libraryDb => DatabaseConstants.databaseFileName,
    LibraryComponent.catalog =>
      DatabaseConstants.externalCatalogDatabaseFileName,
    LibraryComponent.lexicon => DatabaseConstants.lexicalDatabaseFileName,
    LibraryComponent.talmudBavli => DatabaseConstants.talmudBavliFolderName,
    LibraryComponent.searchIndex => throw UnsupportedError(
      'אינדקס אינו נכס גולמי',
    ),
  };
}

/// נכסי הספרייה הגולמיים שבתיקייה. [problem] — ה-DB נמצא כחלקים שאי אפשר
/// לייבא (חלק חסר, מניפסט פגום), ואין גרסה אחרת שלו.
class RawLibraryScan {
  const RawLibraryScan({this.assets = const {}, this.problem});

  final Map<LibraryComponent, RawLibraryAsset> assets;
  final String? problem;

  bool get isEmpty => assets.isEmpty && problem == null;
  int get compressedSize =>
      assets.values.fold(0, (sum, asset) => sum + asset.size);
}

/// מה שנמצא בתיקיית המקור: חבילת המסייע (גוברת) או נכסים גולמיים.
class LibrarySourceScan {
  const LibrarySourceScan({
    required this.folder,
    this.packages = const LibraryPackageScan(),
    this.raw = const RawLibraryScan(),
  });

  final PackageFolder folder;
  final LibraryPackageScan packages;
  final RawLibraryScan raw;

  /// הרכיבים שהייבוא יתקין.
  Set<LibraryComponent> get components {
    final set = packages.packages;
    if (set == null) return raw.assets.keys.toSet();
    // חבילת המסייע היא books/ שלם.
    return {
      LibraryComponent.libraryDb,
      LibraryComponent.talmudBavli,
      LibraryComponent.catalog,
      LibraryComponent.lexicon,
      if (set.index != null) LibraryComponent.searchIndex,
    };
  }
}

Future<LibrarySourceScan> scanLibrarySource(PackageFolder folder) async {
  final packages = await scanLibraryPackages(folder);
  return LibrarySourceScan(
    folder: folder,
    packages: packages,
    raw: packages.packages != null
        ? const RawLibraryScan()
        : await scanRawLibraryAssets(folder),
  );
}

/// מזהה את קובצי הספרייה שבשורש [root] וב-[kLibraryDbSubfolder] שבו;
/// לכל רכיב — הגרסה הראשונה שנמצאה, והשורש קודם.
Future<RawLibraryScan> scanRawLibraryAssets(PackageFolder root) async {
  final folders = [root, ?await root.child(kLibraryDbSubfolder)];
  final assets = <LibraryComponent, RawLibraryAsset>{};
  String? problem;
  for (final folder in folders) {
    final files = {for (final e in await folder.list()) e.name: e};
    if (!assets.containsKey(LibraryComponent.libraryDb)) {
      try {
        final db = await _findDatabase(folder, files);
        if (db != null) assets[LibraryComponent.libraryDb] = db;
      } on FormatException catch (e) {
        problem ??= e.message;
      }
    }
    final found = [
      _single(folder, files, LibraryComponent.catalog, [
        (DatabaseConstants.externalCatalogArchiveFileName, RawAssetFormat.zstd),
        (
          DatabaseConstants.externalCatalogDatabaseFileName,
          RawAssetFormat.plain,
        ),
      ]),
      _single(folder, files, LibraryComponent.lexicon, [
        for (final name in DatabaseConstants.lexicalReleaseAssetFileNames)
          (name, RawAssetFormat.plain),
      ]),
      _single(folder, files, LibraryComponent.talmudBavli, [
        (DatabaseConstants.talmudBavliArchiveFileName, RawAssetFormat.tarZstd),
      ]),
      await _extractedTalmud(folder),
    ];
    for (final asset in found.nonNulls) {
      assets.putIfAbsent(asset.component, () => asset);
    }
  }
  return RawLibraryScan(
    assets: assets,
    problem: assets.containsKey(LibraryComponent.libraryDb) ? null : problem,
  );
}

RawLibraryAsset? _single(
  PackageFolder folder,
  Map<String, PackageFileEntry> files,
  LibraryComponent component,
  List<(String, RawAssetFormat)> candidates,
) {
  for (final (name, format) in candidates) {
    final entry = files[name];
    if (entry == null) continue;
    return RawLibraryAsset(
      component: component,
      format: format,
      folder: folder,
      sourceName: name,
      parts: [LibraryPackagePart(entry: entry)],
    );
  }
  return null;
}

Future<RawLibraryAsset?> _extractedTalmud(PackageFolder folder) async {
  if (folder is! DirectoryPackageFolder) return null;
  final dir = Directory(
    p.join(folder.path, DatabaseConstants.talmudBavliFolderName),
  );
  if (!await dir.exists()) return null;
  return RawLibraryAsset(
    component: LibraryComponent.talmudBavli,
    format: RawAssetFormat.directory,
    folder: folder,
    sourceName: DatabaseConstants.talmudBavliFolderName,
    directoryPath: dir.path,
  );
}

/// סדר העדפה: הסכמה הגבוהה ביותר שהגרסה קוראת (קובץ שלם לפני חלקים),
/// ואחריה seforim.db רגיל.
Future<RawLibraryAsset?> _findDatabase(
  PackageFolder folder,
  Map<String, PackageFileEntry> files,
) async {
  for (final name in DatabaseConstants.supportedDatabaseArchiveFileNames) {
    final whole = _single(folder, files, LibraryComponent.libraryDb, [
      (name, RawAssetFormat.zstd),
    ]);
    if (whole != null) return whole;
    final manifest = files['$name$kSplitManifestSuffix'];
    if (manifest != null) return _fromSplitManifest(folder, files, manifest);
  }
  return _single(folder, files, LibraryComponent.libraryDb, [
    (DatabaseConstants.databaseFileName, RawAssetFormat.plain),
  ]);
}

/// מניפסט בצורת `split_release_asset.sh`; זורק [FormatException] עם שם
/// החלק החסר או הפגום.
Future<RawLibraryAsset> _fromSplitManifest(
  PackageFolder folder,
  Map<String, PackageFileEntry> files,
  PackageFileEntry manifest,
) async {
  final Object? json;
  try {
    final bytes = await folder
        .openRead(manifest)
        .fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw FormatException('הקובץ ${manifest.name} פגום');
  }
  if (json is Map && json['parts'] is List) {
    for (final part in json['parts'] as List) {
      if (part is! Map || part['name'] is! String) continue;
      final entry = files[part['name']];
      if (entry == null) throw FormatException('חסר הקובץ ${part['name']}');
      if (entry.size != part['size']) {
        throw FormatException('הקובץ ${part['name']} אינו שלם');
      }
    }
  }
  final split = SplitAsset.fromManifestJson(
    json,
    manifestName: manifest.name,
    partUrls: {for (final name in files.keys) name: name},
  );
  return RawLibraryAsset(
    component: LibraryComponent.libraryDb,
    format: RawAssetFormat.zstd,
    folder: folder,
    sourceName: split.archive,
    parts: [
      for (final part in split.parts)
        LibraryPackagePart(entry: files[part.name]!, sha256: part.sha256),
    ],
    sha256: split.sha256,
  );
}
