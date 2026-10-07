import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_planner.dart';
import 'package:path/path.dart' as p;

AttachedUpdateArtifact _artifact({
  required AttachedUpdateCompression compression,
  required int size,
  required String sha256,
  required int downloadSize,
  String url = 'https://updates.example.org/lib/part',
}) => AttachedUpdateArtifact(
  compression: compression,
  size: size,
  sha256: sha256,
  parts: [AttachedUpdatePart(url: url, size: downloadSize, sha256: sha256)],
);

void main() {
  late Directory temp;
  late String installed;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('otzaria_delta_plan');
    installed = p.join(temp.path, 'lib.db');
    final bytes = List<int>.generate(4096, (i) => i % 251);
    await File(installed).writeAsBytes(bytes);
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  AttachedUpdateManifest manifest(List<AttachedUpdateDelta> deltas) =>
      AttachedUpdateManifest(
        libraryId: 'lib',
        dbVersion: 3,
        full: _artifact(
          compression: AttachedUpdateCompression.zstd,
          size: 9000,
          sha256: 'a' * 64,
          downloadSize: 5000,
        ),
        deltas: deltas,
      );

  AttachedUpdateDelta delta({
    int fromDbVersion = 2,
    String? fromSha256,
    int downloadSize = 1000,
    String url = 'https://updates.example.org/lib/patch',
  }) => AttachedUpdateDelta(
    fromDbVersion: fromDbVersion,
    fromSha256: fromSha256 ?? 'c' * 64,
    artifact: _artifact(
      compression: AttachedUpdateCompression.zstdPatch,
      size: 9000,
      sha256: 'a' * 64,
      downloadSize: downloadSize,
      url: url,
    ),
  );

  Future<AttachedUpdatePlan> planWith(
    List<AttachedUpdateDelta> deltas, {
    int? pointerSize,
    int maxBaseBytes = kMaxDeltaBaseBytes,
  }) => AttachedUpdateArtifactPlanner(
    pointerSize: pointerSize ?? 8,
    maxBaseBytes: maxBaseBytes,
  ).plan(manifest(deltas), installedPath: installed, installedDbVersion: 2);

  test('picks the smallest applicable delta', () async {
    final small = delta(downloadSize: 700, url: 'https://x.example.org/small');
    final plan = await planWith([delta(downloadSize: 1500), small]);
    expect(plan.isDelta, isTrue);
    expect(plan.delta, same(small));
    expect(plan.artifact.compressedSize, 700);
  });

  test('a delta for another db_version is ignored', () async {
    final plan = await planWith([delta(fromDbVersion: 1)]);
    expect(plan.isDelta, isFalse);
    expect(plan.artifact.compressedSize, 5000);
  });

  test('the installed file contents are not hashed to pick a delta', () async {
    // 2080: sha256 של 1GB ב-Dart לוקח דקות. אי-התאמה של הבסיס נתפסת באימות
    // הפלט מול המניפסט החתום, ושם חוזרים לקובץ המלא.
    final plan = await planWith([delta(fromSha256: 'b' * 64)]);
    expect(plan.isDelta, isTrue);
  });

  test(
    'a delta that is not smaller than the full download is ignored',
    () async {
      final plan = await planWith([delta(downloadSize: 5000)]);
      expect(plan.isDelta, isFalse);
    },
  );

  test('a 32-bit process never uses a delta', () async {
    final plan = await planWith([delta()], pointerSize: 4);
    expect(plan.isDelta, isFalse);
  });

  test('an installed file over the window ceiling is ignored', () async {
    final plan = await planWith([delta()], maxBaseBytes: 100);
    expect(plan.isDelta, isFalse);
  });

  test('a missing installed file falls back to the full artifact', () async {
    await File(installed).delete();
    final plan = await planWith([delta()]);
    expect(plan.isDelta, isFalse);
  });
}
