import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';

InstalledPlugin _plugin(String id) => InstalledPlugin(
  pluginId: id,
  name: 'תוסף $id',
  version: '1.0.0',
  installPath: '/tmp/$id',
  entrypointPath: '/tmp/$id/index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: id,
    name: 'תוסף $id',
    version: '1.0.0',
    description: 'test',
    author: 'tester',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: const ['notifications.system'],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'תוסף $id',
    toolTabOrder: 100,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

/// התוסף תזמן התראה 7; המזהה שמור ב-KV הפנימי כמו בגשר.
class _FakeRepo implements PluginRegistryRepository {
  final plugins = {'p1': _plugin('p1')};

  @override
  Future<InstalledPlugin?> getPlugin(String pluginId) async =>
      plugins[pluginId];
  @override
  Future<String?> getKV(String id, String ns, String key) async =>
      plugins.containsKey(id) && ns == '_internal' && key == 'notification_ids'
      ? '[7]'
      : null;
  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async =>
      [];
  @override
  Future<List<String>> getGrantedPermissionNames(String id) async => [];
  @override
  Future<List<InstalledPlugin>> getAllPlugins() async =>
      plugins.values.toList();
  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// מדמה את ההסרה האמיתית: הרשומה ונתוני ה-KV נמחקים.
class _StubInstaller extends PluginInstallerService {
  _StubInstaller(this.repo) : super(repository: repo);
  final _FakeRepo repo;

  @override
  Future<void> uninstallPlugin(String pluginId) async =>
      repo.plugins.remove(pluginId);
  @override
  Future<void> resetPluginData(String pluginId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final cancelled = <Object?>[];

  setUpAll(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    FlutterLocalNotificationsPlatform.instance =
        MacOSFlutterLocalNotificationsPlugin();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'cancel') cancelled.add(call.arguments);
          return true;
        });
    await NotificationService().init();
  });

  tearDownAll(() => debugDefaultTargetPlatformOverride = null);
  setUp(cancelled.clear);

  Future<void> run(PluginSystemEvent event) async {
    final repo = _FakeRepo();
    final bloc = PluginSystemBloc(
      repository: repo,
      installerService: _StubInstaller(repo),
    );
    addTearDown(bloc.close);
    bloc.add(event);
    await expectLater(bloc.stream, emitsThrough(isA<PluginSystemLoaded>()));
  }

  test('איפוס נתוני התוסף מבטל את ההתראה שתזמן', () async {
    expect(NotificationService().isInitialized, isTrue);
    await run(const ResetPluginDataRequested('p1'));
    expect(cancelled, [7]);
  });

  test('הסרת התוסף מבטלת את ההתראה שתזמן', () async {
    await run(const UninstallPluginRequested('p1'));
    expect(cancelled, [7]);
  });
}
