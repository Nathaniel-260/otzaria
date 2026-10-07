import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'windows/runner/startup_watchdog.cpp',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final mainSource = File('windows/runner/main.cpp').readAsStringSync();
  final windowSource = File(
    'windows/runner/flutter_window.cpp',
  ).readAsStringSync();

  test('ה-watcher אינו מרענן מודולים דרך loader APIs', () {
    final start = source.indexOf('void WatcherLoop()');
    final end = source.indexOf('\n}\n\n}  // namespace', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final watcher = source.substring(start, end);
    expect(watcher, isNot(contains('RefreshModules')));
    expect(watcher, isNot(contains('EnumProcessModules')));
    expect(source, contains('std::atomic_load_explicit(&g_modules'));
  });

  test(
    'ה-heartbeat ב-thread הראשי מרענן מודולים שנטענו מאוחר (issue #2064)',
    () {
      final start = source.indexOf('void CALLBACK HeartbeatProc(');
      final end = source.indexOf('\n}', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(source.substring(start, end), contains('RefreshModules();'));
    },
  );

  test('כשל timer אינו מפעיל watcher', () {
    final timer = source.indexOf('g_timer = ::SetTimer');
    final failed = source.indexOf('if (g_timer == 0)', timer);
    final watcher = source.indexOf('g_watcher = std::thread', timer);
    expect(timer, greaterThanOrEqualTo(0));
    expect(failed, greaterThan(timer));
    expect(watcher, greaterThan(failed));
  });

  test('חשיפה מבקשת עצירה והיציאה משלימה join', () {
    expect(windowSource, contains('startup_watchdog::RequestStop();'));
    final stop = source.substring(source.indexOf('void Stop()'));
    expect(stop, contains('RequestStop();'));
    expect(stop, contains('g_watcher.joinable()'));
    expect(stop, contains('g_watcher.join()'));
  });

  test('יצירת חלון מרעננת snapshot וכשל מנקה משאבים', () {
    final failure = mainSource.indexOf(
      'if (!window.Create(kMainWindowTitle, origin, size))',
    );
    final refresh = mainSource.indexOf(
      'startup_watchdog::RefreshModules();',
      failure,
    );
    expect(failure, greaterThanOrEqualTo(0));
    expect(refresh, greaterThan(failure));
    final failureBlock = mainSource.substring(failure, refresh);
    expect(failureBlock, contains('startup_watchdog::Stop();'));
    expect(failureBlock, contains('splash::Close();'));
    expect(failureBlock, contains('::CoUninitialize();'));
  });
}
