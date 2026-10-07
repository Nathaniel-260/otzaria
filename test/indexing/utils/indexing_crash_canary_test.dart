import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/utils/indexing_crash_canary.dart';
import 'package:path/path.dart' as p;

void main() {
  test('ספר שבטיסה בסגירה מסודרת אינו נספר כקריסה (issue #2038)', () async {
    final tempDir = await Directory.systemTemp.createTemp('canary_');
    addTearDown(() => tempDir.delete(recursive: true));
    final index = p.join(tempDir.path, 'index');
    File('$index.in_flight.json').writeAsStringSync(jsonEncode({'a': 1}));

    IndexingCrashCanary.start(index);
    final canary = IndexingCrashCanary.current!;
    expect(canary.recovering, isTrue);
    expect(canary.begin('a'), isTrue);
    canary.finish();
    expect(IndexingCrashCanary.current, isNull);

    IndexingCrashCanary.start(index);
    expect(IndexingCrashCanary.current!.recovering, isFalse);
    IndexingCrashCanary.current!.finish();
  });
}
