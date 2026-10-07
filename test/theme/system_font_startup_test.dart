import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    AppFonts.debugResetSystemFontsCache();
    directory = Directory.systemTemp.createTempSync('otzaria-font-startup-');
  });

  tearDown(() {
    AppFonts.debugResetSystemFontsCache();
    debugDefaultTargetPlatformOverride = null;
    directory.deleteSync(recursive: true);
  });

  test(
    'regular נטען מוקדם ובולד בשם שרירותי משלים את הרינדור בחימום',
    () async {
      final regular = _face(directory, 'PrAa-regular.ttf', 'PrAa', false);
      final bold = _face(directory, 'opaque-bold.ttf', 'PrAa', true);
      AppFonts.debugScanFamily = (_) async =>
          AppFonts.debugBuildScan([regular]);

      await AppFonts.ensureFontLoaded('PrAa');
      expect(AppFonts.debugWarmUpFuture, isNull);
      expect(AppFonts.hasSeparateBoldFace('PrAa'), isFalse);
      final before = _width('PrAa', FontWeight.bold);
      await _loadReference('PrAaExpectedBold', bold.value);
      final expected = _width('PrAaExpectedBold', FontWeight.bold);
      expect(before, isNot(closeTo(expected, 0.01)));

      await AppFonts.debugStoreScan(AppFonts.debugBuildScan([regular, bold]));
      await AppFonts.ensureFontLoaded('PrAa');
      expect(AppFonts.hasSeparateBoldFace('PrAa'), isTrue);
      expect(_width('PrAa', FontWeight.bold), closeTo(expected, 0.01));
    },
  );

  test('התאמה לבולד בלבד אינה מציגה אותו במקום regular בשם שרירותי', () async {
    final regular = _face(directory, 'opaque-regular.ttf', 'PrBb', false);
    final bold = _face(directory, 'PrBb-bold.ttf', 'PrBb', true);
    AppFonts.debugScanFamily = (_) async => AppFonts.debugBuildScan([bold]);
    final finishScan = Completer<void>();
    AppFonts.debugWarmUpFuture = finishScan.future.then(
      (_) => AppFonts.debugStoreScan(AppFonts.debugBuildScan([regular, bold])),
    );
    var loaded = false;
    final loading = AppFonts.ensureFontLoaded(
      'PrBb',
    ).then((_) => loaded = true);
    await Future<void>.delayed(Duration.zero);
    expect(loaded, isFalse);
    finishScan.complete();
    await loading.timeout(const Duration(seconds: 5));

    await _loadReference('PrBbExpectedRegular', regular.value);
    expect(
      _width('PrBb', FontWeight.normal),
      closeTo(_width('PrBbExpectedRegular', FontWeight.normal), 0.01),
    );
    expect(AppFonts.hasSeparateBoldFace('PrBb'), isTrue);
  });

  test('תמיכה בטעמים מפורסמת בטעינה מוקדמת גם בהשוואה ללא רישיות', () async {
    final regular = _face(
      directory,
      'PrCc-regular.ttf',
      'PrCc',
      false,
      source: 'fonts/Rubik-VariableFont_wght.ttf',
      weight: 400,
    );
    AppFonts.debugScanFamily = (_) async => AppFonts.debugBuildScan([regular]);
    await AppFonts.ensureFontLoaded('PrCc');

    expect(AppFonts.debugSystemFontsHebrewCache, isNull);
    expect(AppFonts.familySupportsTaamim('prcc'), isFalse);
    expect(
      AppFonts.taamimSafeFontFamily('PrCc', 'בְּרֵאשִׁ֖ית'),
      AppFonts.defaultFont,
    );
  });

  test('סריקה ממוקדת שמסתיימת אחרי החימום משתמשת במשפחה המלאה', () async {
    final regular = _face(directory, 'PrDd-regular.ttf', 'PrDd', false);
    final bold = _face(directory, 'opaque-bold.ttf', 'PrDd', true);
    final targeted = Completer<SystemFontScanResult>();
    AppFonts.debugScanFamily = (_) => targeted.future;
    final loading = AppFonts.ensureFontLoaded('PrDd');
    await AppFonts.debugStoreScan(AppFonts.debugBuildScan([regular, bold]));
    targeted.complete(AppFonts.debugBuildScan([regular]));
    await loading.timeout(const Duration(seconds: 5));

    await _loadReference('PrDdExpectedBold', bold.value);
    expect(AppFonts.hasSeparateBoldFace('PrDd'), isTrue);
    expect(
      _width('PrDd', FontWeight.bold),
      closeTo(_width('PrDdExpectedBold', FontWeight.bold), 0.01),
    );
  });

  test('חימום בזמן טעינת ה-regular משלים faces בלי המתנה מעגלית', () async {
    final regular = _face(directory, 'PrFf-regular.ttf', 'PrFf', false);
    final bold = _face(directory, 'opaque-bold.ttf', 'PrFf', true);
    final targeted = Completer<SystemFontScanResult>();
    AppFonts.debugScanFamily = (_) => targeted.future;
    var loaded = false;
    final loading = AppFonts.ensureFontLoaded(
      'PrFf',
    ).then((_) => loaded = true);
    targeted.complete(AppFonts.debugBuildScan([regular]));
    await Future<void>.value();
    expect(loaded, isFalse);
    expect(AppFonts.debugSystemFontsHebrewCache, isNull);
    final warming = AppFonts.debugStoreScan(
      AppFonts.debugBuildScan([regular, bold]),
    );
    await Future.wait([loading, warming]).timeout(const Duration(seconds: 5));
    await AppFonts.ensureFontLoaded('PrFf');

    await _loadReference('PrFfExpectedBold', bold.value);
    expect(
      _width('PrFf', FontWeight.bold),
      closeTo(_width('PrFfExpectedBold', FontWeight.bold), 0.01),
    );
  });

  test('טעינה מוקדמת שנכשלה אינה נשארת בתור ההשלמה וניתן לנסות שוב', () async {
    final regular = _face(directory, 'PrGg-regular.ttf', 'PrGg', false);
    final scan = AppFonts.debugBuildScan([regular]);
    AppFonts.debugScanFamily = (_) async => scan;
    File(regular.key).deleteSync();
    await AppFonts.ensureFontLoaded('PrGg');
    File(regular.key).writeAsBytesSync(regular.value);

    await AppFonts.debugStoreScan(scan);
    await AppFonts.ensureFontLoaded('PrGg');
    await _loadReference('PrGgExpectedRegular', regular.value);
    expect(
      _width('PrGg', FontWeight.normal),
      closeTo(_width('PrGgExpectedRegular', FontWeight.normal), 0.01),
    );
  });

  test('Medium אינו נחשב ל-regular בטוח לטעינה מוקדמת', () async {
    final medium = _face(
      directory,
      'PrEe-medium.ttf',
      'PrEe',
      false,
      source: 'fonts/FrankRuehlCLM-Medium.ttf',
    );
    final regular = _face(directory, 'opaque-regular.ttf', 'PrEe', false);
    AppFonts.debugScanFamily = (_) async => AppFonts.debugBuildScan([medium]);
    final finishScan = Completer<void>();
    AppFonts.debugWarmUpFuture = finishScan.future.then(
      (_) =>
          AppFonts.debugStoreScan(AppFonts.debugBuildScan([medium, regular])),
    );
    var loaded = false;
    final loading = AppFonts.ensureFontLoaded(
      'PrEe',
    ).then((_) => loaded = true);
    await Future<void>.delayed(Duration.zero);
    expect(loaded, isFalse);
    finishScan.complete();
    await loading.timeout(const Duration(seconds: 5));
    expect(AppFonts.systemFamilyFaces('PrEe')!.regularPath, regular.key);
  });
}

MapEntry<String, Uint8List> _face(
  Directory directory,
  String filename,
  String family,
  bool bold, {
  String? source,
  int? weight,
}) {
  final bytes = File(
    source ??
        (bold ? 'fonts/FrankRuehlCLM-Bold.ttf' : 'fonts/Tinos-Regular.ttf'),
  ).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  final tables = data.getUint16(4);
  for (var i = 0; i < tables; i++) {
    final record = 12 + i * 16;
    final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
    if (tag == 'OS/2' && weight != null) {
      data.setUint16(data.getUint32(record + 8) + 4, weight);
    }
    if (tag != 'name') {
      continue;
    }
    final table = data.getUint32(record + 8);
    final storage = table + data.getUint16(table + 4);
    for (var j = 0; j < data.getUint16(table + 2); j++) {
      final name = table + 6 + j * 12;
      final id = data.getUint16(name + 6);
      if (id != 1 && id != 16) continue;
      final unicode = data.getUint16(name) != 1;
      final encoded = unicode
          ? family.codeUnits.expand((unit) => [unit >> 8, unit & 0xff]).toList()
          : family.codeUnits;
      expect(encoded.length, lessThanOrEqualTo(data.getUint16(name + 8)));
      final start = storage + data.getUint16(name + 10);
      bytes.setRange(start, start + encoded.length, encoded);
      data.setUint16(name + 8, encoded.length);
    }
  }
  final file = File('${directory.path}/$filename')..writeAsBytesSync(bytes);
  return MapEntry(file.path, bytes);
}

Future<void> _loadReference(String family, Uint8List bytes) => (FontLoader(
  family,
)..addFont(Future.value(ByteData.sublistView(bytes)))).load();

double _width(String family, FontWeight weight) {
  final painter = TextPainter(
    text: TextSpan(
      text: 'minimum maximum abc אבג',
      style: TextStyle(fontFamily: family, fontSize: 48, fontWeight: weight),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
