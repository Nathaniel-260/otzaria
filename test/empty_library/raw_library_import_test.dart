import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_extractor.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_importer.dart';
import 'package:otzaria/empty_library/services/library_package/library_source.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/empty_library/services/library_package/raw_asset_extractor.dart';
import 'package:otzaria/search/magic_dictionary_downloader.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:path/path.dart' as p;

import '../support/zstd_test_lib.dart';
import '../test_helpers/memory_cache_provider.dart';
import 'library_package_test_support.dart';

/// תיקייה בזיכרון — כמו עץ SAF: אין לה נתיב, והקריאה בנתחים.
class _MemoryFolder extends PackageFolder {
  _MemoryFolder(
    this.name, {
    Map<String, List<int>>? files,
    Map<String, _MemoryFolder>? children,
  }) : files = files ?? {},
       children = children ?? {};

  final String name;
  final Map<String, List<int>> files;
  final Map<String, _MemoryFolder> children;

  @override
  String get displayName => name;

  @override
  Future<List<PackageFileEntry>> list() async => [
    for (final MapEntry(:key, :value) in files.entries)
      PackageFileEntry(name: key, size: value.length, id: '$name/$key'),
  ];

  @override
  Future<PackageFolder?> child(String name) async => children[name];

  @override
  Stream<List<int>> openRead(PackageFileEntry entry) async* {
    final bytes = files[entry.name]!;
    for (var offset = 0; offset < bytes.length; offset += 7000) {
      yield bytes.sublist(offset, min(offset + 7000, bytes.length));
    }
  }
}

Uint8List _noise(int length, int seed) {
  final random = Random(seed);
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

/// חלקים ומניפסט בצורת `split_release_asset.sh`.
Map<String, List<int>> _split(String archiveName, List<int> archive, int size) {
  final files = <String, List<int>>{};
  final parts = <Map<String, Object>>[];
  for (var offset = 0, i = 0; offset < archive.length; offset += size, i++) {
    final bytes = archive.sublist(offset, min(offset + size, archive.length));
    final name = '$archiveName.part-${i.toString().padLeft(3, '0')}';
    files[name] = bytes;
    parts.add({
      'name': name,
      'size': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
    });
  }
  files['$archiveName.manifest.json'] = utf8.encode(
    jsonEncode({
      'schemaVersion': 1,
      'archive': archiveName,
      'size': archive.length,
      'sha256': sha256.convert(archive).toString(),
      'parts': parts,
    }),
  );
  return files;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final lib = openZstdForTests();
  final dbName = DatabaseConstants.databaseFileName;
  final talmud = DatabaseConstants.talmudBavliFolderName;

  late Directory temp;
  late String books;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('otzaria-raw-import-');
    EmptyLibraryBloc.tempRootOverride = temp.path;
    books = p.join(temp.path, 'ספרייה', 'books');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
  });

  tearDown(() async {
    EmptyLibraryBloc.tempRootOverride = null;
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// הפריסה האמיתית בלי isolate: ב-isolate של בדיקה אין את ה-DLL של zstd.
  Future<void> inlineRunner(
    RawAssetJob job, {
    required RawAssetProgress onProgress,
    required ZstdCancelFlag cancel,
  }) {
    final cell = Pointer<Uint8>.fromAddress(cancel.address);
    return extractRawAssetJob(
      job,
      openZstd: () => lib!,
      onProgress: onProgress,
      isCancelled: () => cell.value != 0,
    );
  }

  EmptyLibraryBloc build({RawAssetRunner? runner}) => EmptyLibraryBloc(
    downloadSpaceChecker: (_) async => null,
    packageImporter: LibraryPackageImporter(
      rawRunner: runner ?? inlineRunner,
      diskSpace: (_) async => DiskSpaceInfo.unknown,
    ),
  );

  Future<EmptyLibraryState> import(
    EmptyLibraryBloc bloc,
    PackageFolder folder,
  ) async {
    final done = bloc.stream
        .where(
          (s) => s is EmptyLibraryDirectorySelected || s is EmptyLibraryError,
        )
        .first;
    bloc.add(
      ImportLibraryFolderRequested(
        assets: await scanRawLibraryAssets(folder),
        targetPath: books,
      ),
    );
    return done.timeout(const Duration(seconds: 30));
  }

  void expectNoLeftovers() {
    expect(Directory('$books.import').existsSync(), isFalse);
    expect(Directory(EmptyLibraryBloc.dbBackupDirPath).existsSync(), isFalse);
  }

  final pdf = _noise(300000, 1);
  late Uint8List talmudArchive;

  /// כמו otzaria-android-full: library_db/ מתוך part1, והתלמוד מ-part2 בשורש.
  _MemoryFolder fullBundle(DynamicLibrary lib) {
    talmudArchive = zstdCompress(lib, buildTar({'$talmud/ברכות.pdf': pdf}));
    return _MemoryFolder(
      'Download/otzaria',
      files: {
        'app-release.apk': [1, 2, 3],
        DatabaseConstants.talmudBavliArchiveFileName: talmudArchive,
      },
      children: {
        kLibraryDbSubfolder: _MemoryFolder(
          'Download/otzaria/library_db',
          files: {
            DatabaseConstants.databaseArchiveFileName: zstdCompress(
              lib,
              utf8.encode('new-db'),
            ),
            DatabaseConstants.externalCatalogArchiveFileName: zstdCompress(
              lib,
              utf8.encode('catalog-db'),
            ),
            DatabaseConstants.lexicalDatabaseFileName: utf8.encode('lexical'),
          },
        ),
      },
    );
  }

  test('סריקה: חבילת אנדרואיד המלאה מזוהה בשורש וב-library_db', () async {
    if (lib == null) return markTestSkipped('libzstd אינו זמין');
    final scan = await scanRawLibraryAssets(fullBundle(lib));

    expect(scan.problem, isNull);
    expect(scan.assets.keys.toSet(), {
      LibraryComponent.libraryDb,
      LibraryComponent.catalog,
      LibraryComponent.lexicon,
      LibraryComponent.talmudBavli,
    });
    final db = scan.assets[LibraryComponent.libraryDb]!;
    expect(db.format, RawAssetFormat.zstd);
    expect(db.folder.displayName, 'Download/otzaria/library_db');
    expect(
      scan.assets[LibraryComponent.talmudBavli]!.format,
      RawAssetFormat.tarZstd,
    );
  });

  test('ייבוא חבילת אנדרואיד המלאה: כל הרכיבים מגיעים ליעד', () async {
    if (lib == null) return markTestSkipped('libzstd אינו זמין');
    final bloc = build();
    addTearDown(bloc.close);

    final state = await import(bloc, fullBundle(lib));

    expect(state, isA<EmptyLibraryDirectorySelected>());
    expect(File(p.join(books, dbName)).readAsStringSync(), 'new-db');
    expect(
      File(
        p.join(books, DatabaseConstants.externalCatalogDatabaseFileName),
      ).readAsStringSync(),
      'catalog-db',
    );
    final lexical = p.join(books, DatabaseConstants.lexicalDatabaseFileName);
    expect(File(lexical).readAsStringSync(), 'lexical');
    expect(
      File('$lexical.version').readAsStringSync(),
      sha256.convert(utf8.encode('lexical')).toString(),
    );
    expect(File(p.join(books, talmud, 'ברכות.pdf')).readAsBytesSync(), pdf);
    // ה-digest של הארכיון הוא מה שבדיקת העדכונים משווה, ולכן התלמוד לא יורד שוב.
    expect(
      File(
        DatabaseConstants.talmudBavliVersionFilePath(p.join(books, talmud)),
      ).readAsStringSync(),
      sha256.convert(talmudArchive).toString(),
    );
    expect(
      Settings.getValue<String>(SettingsRepository.keyLibraryPath),
      books,
    );
    final report = (state as EmptyLibraryDirectorySelected).importReport!;
    expect(report.imported, {
      LibraryComponent.libraryDb,
      LibraryComponent.catalog,
      LibraryComponent.lexicon,
      LibraryComponent.talmudBavli,
    });
    expect(report.missing, {LibraryComponent.searchIndex});
    expectNoLeftovers();
  });

  test('DB מפוצל עם מניפסט נפרס חלק אחר חלק, בלי קובץ מחובר', () async {
    if (lib == null) return markTestSkipped('libzstd אינו זמין');
    final dbBytes = _noise(200000, 2);
    final archive = zstdCompress(lib, dbBytes);
    final name = DatabaseConstants.supportedDatabaseArchiveFileNames.first;
    final folder = _MemoryFolder('split', files: _split(name, archive, 50000));
    final bloc = build();
    addTearDown(bloc.close);

    final state = await import(bloc, folder);

    expect(state, isA<EmptyLibraryDirectorySelected>());
    expect(File(p.join(books, dbName)).readAsBytesSync(), dbBytes);
    expect(
      Directory(p.dirname(books))
          .listSync(recursive: true)
          .map((e) => p.basename(e.path))
          .where((n) => n.contains('.part-') || n.contains('.joining')),
      isEmpty,
    );
    final report = (state as EmptyLibraryDirectorySelected).importReport!;
    expect(report.missing, {
      LibraryComponent.talmudBavli,
      LibraryComponent.catalog,
      LibraryComponent.lexicon,
      LibraryComponent.searchIndex,
    });
    expectNoLeftovers();
  });

  test('חלק חסר: הסריקה מדווחת את שם הקובץ ואין DB לייבוא', () async {
    final archive = _noise(3000, 3);
    final name = DatabaseConstants.supportedDatabaseArchiveFileNames.first;
    final files = _split(name, archive, 1000)..remove('$name.part-001');

    final scan = await scanRawLibraryAssets(_MemoryFolder('x', files: files));

    expect(scan.assets.containsKey(LibraryComponent.libraryDb), isFalse);
    expect(scan.problem, 'חסר הקובץ $name.part-001');
  });

  test('חלק פגום: שגיאה ברורה, הספרייה הקיימת נשמרת ואין שאריות', () async {
    if (lib == null) return markTestSkipped('libzstd אינו זמין');
    await Directory(books).create(recursive: true);
    await File(p.join(books, dbName)).writeAsString('old-db');
    final archive = zstdCompress(lib, _noise(200000, 4));
    final name = DatabaseConstants.supportedDatabaseArchiveFileNames.first;
    final files = _split(name, archive, 50000);
    final corrupt = List<int>.of(files['$name.part-001']!);
    corrupt[10] ^= 0xFF;
    files['$name.part-001'] = corrupt;
    final bloc = build();
    addTearDown(bloc.close);

    final state = await import(bloc, _MemoryFolder('x', files: files));

    expect(state, isA<EmptyLibraryError>());
    expect(
      state.errorMessage,
      allOf(contains('$name.part-001'), contains('פגום')),
    );
    expect(File(p.join(books, dbName)).readAsStringSync(), 'old-db');
    expectNoLeftovers();
  });

  test('כשל באמצע הפריסה אינו נוגע ב-DB שביעד ומוחק את ה-staging', () async {
    await Directory(books).create(recursive: true);
    await File(p.join(books, dbName)).writeAsString('existing-db');
    final bloc = build(
      runner: (job, {required onProgress, required cancel}) async {
        await File(p.join(job.destination, dbName)).writeAsString('partial');
        throw const FileSystemException('killed');
      },
    );
    addTearDown(bloc.close);

    final state = await import(
      bloc,
      _MemoryFolder('x', files: {dbName: utf8.encode('db')}),
    );

    expect(state, isA<EmptyLibraryError>());
    expect(File(p.join(books, dbName)).readAsStringSync(), 'existing-db');
    expectNoLeftovers();
  });

  test('ביטול בזמן הפריסה: הודעת ביטול ואין שאריות', () async {
    final started = Completer<void>();
    final bloc = build(
      runner: (job, {required onProgress, required cancel}) async {
        onProgress(LibraryComponent.libraryDb, 1, 10);
        started.complete();
        final cell = Pointer<Uint8>.fromAddress(cancel.address);
        while (cell.value == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        throw const LibraryImportCancelled();
      },
    );
    addTearDown(bloc.close);
    final done = bloc.stream.where((s) => s is EmptyLibraryError).first;
    bloc.add(
      ImportLibraryFolderRequested(
        assets: await scanRawLibraryAssets(
          _MemoryFolder('x', files: {dbName: utf8.encode('db')}),
        ),
        targetPath: books,
      ),
    );
    await started.future.timeout(const Duration(seconds: 10));
    bloc.add(CancelLibraryImportRequested());

    final state = await done.timeout(const Duration(seconds: 10));
    expect(state.errorMessage, 'הייבוא בוטל. הספרייה לא שונתה.');
    expect(File(p.join(books, dbName)).existsSync(), isFalse);
    expectNoLeftovers();
  });

  test('בלי DB בתיקייה ובלי ספרייה ביעד: שגיאה ברורה ולא "הושלם"', () async {
    final bloc = build();
    addTearDown(bloc.close);

    final state = await import(
      bloc,
      _MemoryFolder('x', files: {'lexical.db': utf8.encode('lex')}),
    );

    expect(state, isA<EmptyLibraryError>());
    expect(state.errorMessage, contains('לא נמצא $dbName'));
    expectNoLeftovers();
  });

  test('תיקייה רגילה: קבצים לא דחוסים ותיקיית תלמוד מחולצת', () async {
    final src = await Directory(p.join(temp.path, 'src')).create();
    await File(p.join(src.path, dbName)).writeAsString('db');
    await File(p.join(src.path, 'lexical.db')).writeAsString('lex');
    // הנכס החדש עדיף על lexical.db הקפוא, ומותקן בשם המקומי.
    await File(p.join(src.path, 'lexical-v2.db')).writeAsString('lex2');
    await File(
      p.join(src.path, DatabaseConstants.externalCatalogDatabaseFileName),
    ).writeAsString('cat');
    await Directory(p.join(src.path, talmud)).create();
    await File(p.join(src.path, talmud, 'שבת.pdf')).writeAsString('pdf');
    final lexicalTarget = p.join(books, 'lexical.db');
    await Directory(books).create(recursive: true);
    await File('$lexicalTarget.next').writeAsString('staged-old');
    await File('$lexicalTarget.next.version').writeAsString('old-digest');
    final bloc = build();
    addTearDown(bloc.close);

    final state = await import(bloc, DirectoryPackageFolder(src.path));

    expect(state, isA<EmptyLibraryDirectorySelected>());
    expect(File(p.join(books, dbName)).readAsStringSync(), 'db');
    await MagicDictionaryDownloader.installStagedBeforeAttach(lexicalTarget);
    expect(File(lexicalTarget).readAsStringSync(), 'lex2');
    expect(File('$lexicalTarget.next').existsSync(), isFalse);
    expect(
      File('$lexicalTarget.version').readAsStringSync(),
      sha256.convert(utf8.encode('lex2')).toString(),
    );
    expect(
      File(
        p.join(books, DatabaseConstants.externalCatalogDatabaseFileName),
      ).readAsStringSync(),
      'cat',
    );
    expect(File(p.join(books, talmud, 'שבת.pdf')).readAsStringSync(), 'pdf');
    expect(File(p.join(src.path, dbName)).existsSync(), isTrue);
    expectNoLeftovers();
  });

  test('runRawAssetJobInIsolate פורס מתיקייה רגילה ב-isolate', () async {
    if (lib == null) return markTestSkipped('libzstd אינו זמין');
    final src = await Directory(p.join(temp.path, 'src', 'library_db')).create(
      recursive: true,
    );
    await File(
      p.join(src.path, DatabaseConstants.databaseArchiveFileName),
    ).writeAsBytes(zstdCompress(lib, utf8.encode('isolated-db')));
    final dest = await Directory(p.join(temp.path, 'dest')).create();
    final scan = await scanRawLibraryAssets(
      DirectoryPackageFolder(p.dirname(src.path)),
    );
    final cancel = ZstdCancelFlag();
    addTearDown(cancel.dispose);
    final progress = <int>[];

    await runRawAssetJobInIsolate(
      RawAssetJob(assets: scan.assets.values.toList(), destination: dest.path),
      onProgress: (_, done, _) => progress.add(done),
      cancel: cancel,
      openZstd: () => openZstdForTests()!,
    );

    expect(File(p.join(dest.path, dbName)).readAsStringSync(), 'isolated-db');
    expect(progress.last, scan.compressedSize);
  });

  group('SafPackageFolder', () {
    const channel = MethodChannel('otzaria/folder_import');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'childFolder' =>
                call.arguments['name'] == kLibraryDbSubfolder
                    ? 'doc:library_db'
                    : null,
              'listFiles' => [
                {'id': 'doc:a', 'name': 'seforim.db', 'size': 3},
              ],
              _ => null,
            };
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('תת-תיקייה נמצאת לפי שם ונמנית לפי מזהה המסמך שלה', () async {
      const root = SafPackageFolder(treeUri: 'content://tree', name: 'otzaria');

      final child = await root.child(kLibraryDbSubfolder);
      expect(await root.child('אחר'), isNull);
      final files = await child!.list();

      expect(child.displayName, 'otzaria/library_db');
      expect(files.single.name, 'seforim.db');
      expect(calls.first.arguments, {
        'uri': 'content://tree',
        'parentId': null,
        'name': kLibraryDbSubfolder,
      });
      expect(calls.last.method, 'listFiles');
      expect(calls.last.arguments, {
        'uri': 'content://tree',
        'parentId': 'doc:library_db',
      });
    });
  });
}
