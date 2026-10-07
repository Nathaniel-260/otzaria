import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// קובץ בתיקיית המקור. [id] מזהה את המסמך ב-SAF; בתיקייה רגילה הוא null.
class PackageFileEntry {
  const PackageFileEntry({required this.name, required this.size, this.id});

  final String name;
  final int size;
  final String? id;
}

/// תיקייה שבה מונחים קובצי הספרייה (חבילת המסייע או הקבצים עצמם). המימושים
/// מחזיקים מחרוזות בלבד, ולכן ניתן להעביר אותם ל-isolate שפורס.
abstract class PackageFolder {
  const PackageFolder();

  /// הקבצים שבשורש התיקייה (בלי תתי-תיקיות).
  Future<List<PackageFileEntry>> list();

  /// שמות תתי-התיקיות שישירות בתיקייה.
  Future<List<String>> folderNames();

  /// תת-התיקייה [name], או null כשאינה קיימת.
  Future<PackageFolder?> child(String name);

  Stream<List<int>> openRead(PackageFileEntry entry);

  /// תיאור לתצוגה ולהודעות שגיאה.
  String get displayName;
}

class DirectoryPackageFolder extends PackageFolder {
  const DirectoryPackageFolder(this.path);

  final String path;

  @override
  String get displayName => path;

  @override
  Future<List<PackageFileEntry>> list() async {
    final entries = <PackageFileEntry>[];
    await for (final entity in Directory(path).list(followLinks: true)) {
      if (entity is! File) continue;
      entries.add(
        PackageFileEntry(
          name: p.basename(entity.path),
          size: await entity.length(),
        ),
      );
    }
    return entries;
  }

  @override
  Future<List<String>> folderNames() async => [
    await for (final entity in Directory(path).list(followLinks: true))
      if (entity is Directory) p.basename(entity.path),
  ];

  @override
  Future<PackageFolder?> child(String name) async {
    final dir = p.join(path, name);
    return await Directory(dir).exists() ? DirectoryPackageFolder(dir) : null;
  }

  @override
  Stream<List<int>> openRead(PackageFileEntry entry) =>
      File(p.join(path, entry.name)).openRead();
}

/// תיקייה שנבחרה ב-SAF באנדרואיד: ל-dart:io אין גישה אליה, והקריאה עוברת
/// בנתחים דרך `FolderImportChannel.kt`. מתוך isolate נדרש קודם
/// `BackgroundIsolateBinaryMessenger.ensureInitialized`.
class SafPackageFolder extends PackageFolder {
  const SafPackageFolder({
    required this.treeUri,
    required this.name,
    this.documentId,
  });

  final String treeUri;
  final String name;

  /// מזהה תת-תיקייה בתוך העץ; null — שורש העץ שנבחר.
  final String? documentId;

  static const _channel = MethodChannel('otzaria/folder_import');
  static const _chunkBytes = 4 << 20;

  @override
  String get displayName => name;

  @override
  Future<List<PackageFileEntry>> list() async {
    final files = await _channel.invokeListMethod<Map>('listFiles', {
      'uri': treeUri,
      'parentId': documentId,
    });
    return [
      for (final file in files ?? const <Map>[])
        PackageFileEntry(
          name: file['name'] as String,
          size: file['size'] as int,
          id: file['id'] as String,
        ),
    ];
  }

  @override
  Future<List<String>> folderNames() async =>
      await _channel.invokeListMethod<String>('listFolders', {
        'uri': treeUri,
        'parentId': documentId,
      }) ??
      const [];

  @override
  Future<PackageFolder?> child(String name) async {
    final id = await _channel.invokeMethod<String>('childFolder', {
      'uri': treeUri,
      'parentId': documentId,
      'name': name,
    });
    return id == null
        ? null
        : SafPackageFolder(
            treeUri: treeUri,
            name: '${this.name}/$name',
            documentId: id,
          );
  }

  @override
  Stream<List<int>> openRead(PackageFileEntry entry) async* {
    final handle = await _channel.invokeMethod<int>('openDocument', {
      'uri': treeUri,
      'id': entry.id,
    });
    try {
      while (true) {
        final chunk = await _channel.invokeMethod<Uint8List>('readDocument', {
          'handle': handle,
          'max': _chunkBytes,
        });
        if (chunk == null || chunk.isEmpty) break;
        yield chunk;
      }
    } finally {
      await _channel.invokeMethod<void>('closeDocument', {'handle': handle});
    }
  }
}
