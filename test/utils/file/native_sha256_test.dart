import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/native_sha256.dart';

void main() {
  late Directory dir;
  setUpAll(() => dir = Directory.systemTemp.createTempSync('native_sha_'));
  tearDownAll(() => dir.deleteSync(recursive: true));

  final nativeSupported = Platform.isWindows;
  const chunk = 8 * 1024 * 1024;
  final rnd = Random(7);

  for (final size in [
    0,
    1,
    55,
    64,
    chunk - 1,
    chunk,
    chunk + 1,
    10 * 1024 * 1024,
    2 * chunk + 5,
  ]) {
    test('זהה ל-package:crypto בגודל $size', () async {
      final bytes = Uint8List.fromList(
        List.generate(size, (_) => rnd.nextInt(256)),
      );
      final file = File('${dir.path}/f$size')..writeAsBytesSync(bytes);
      expect(
        await sha256OfFileFast(file.path),
        sha256.convert(bytes).toString(),
      );
    }, skip: nativeSupported ? false : 'אין מימוש נייטיבי בפלטפורמה זו');
  }

  test('כשל טעינת הספרייה נופל ל-package:crypto', () async {
    final bytes = Uint8List.fromList(
      List.generate(1000, (_) => rnd.nextInt(256)),
    );
    final file = File('${dir.path}/fallback')..writeAsBytesSync(bytes);
    final digest = await sha256OfFileFast(
      file.path,
      loadNative: () => throw ArgumentError('simulated load failure'),
    );
    expect(digest, sha256.convert(bytes).toString());
  });

  test('קובץ חסר: PathNotFoundException ולא נבלע', () async {
    await expectLater(
      sha256OfFileFast('${dir.path}/missing'),
      throwsA(isA<PathNotFoundException>()),
    );
  });
}
