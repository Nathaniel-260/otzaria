import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_slot.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/workspaces/workspace.dart';

import '../helpers/memory_settings_cache.dart';

Map<String, dynamic> pdfJson(String title) => PdfBookTab(
  book: PdfBook(title: title, path: '/tmp/$title.pdf'),
  pageNumber: 1,
).toJson();

/// טאב שהמפענח אינו מכיר, ולכן מדלגים עליו.
const Map<String, dynamic> unknownTab = {'type': 'FutureTab', 'title': 'x'};

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late UserStateDatabase database;
  late WindowSessionStore sessions;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('restore_skipped_tab');
    MultiWindowService.debugSupportedOverride = false;
    database = UserStateDatabase.openAt(p.join(tempDir.path, 'user_state.db'));
    await database.database;
    sessions = WindowSessionStore(database: database);
  });

  tearDown(() async {
    database.close();
    MultiWindowService.debugSupportedOverride = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'session restore keeps the active tab when an earlier tab is skipped',
    () async {
      await sessions.save(
        UserStateSlot.single,
        tabsJson: jsonEncode([
          unknownTab,
          pdfJson('A'),
          pdfJson('B'),
          pdfJson('C'),
        ]),
        currentIndex: 2,
      );
      final bloc = TabsBloc(repository: TabsRepository(sessions: sessions));
      addTearDown(bloc.close);
      bloc.add(LoadTabs());
      await bloc.stream.firstWhere((s) => s.tabs.isNotEmpty);

      expect(bloc.state.tabs.map((t) => t.title), ['A', 'B', 'C']);
      expect(bloc.state.currentTab!.title, 'B');
    },
  );

  test(
    'workspace restore keeps the active tab when an earlier tab is skipped',
    () {
      final ws = Workspace.fromJson({
        'id': 'w',
        'name': 'w',
        'tabs': [unknownTab, pdfJson('A'), pdfJson('B'), pdfJson('C')],
        'currentTab': 2,
      });

      expect(ws.tabs.map((t) => t.title), ['A', 'B', 'C']);
      expect(ws.tabs[ws.activeTabIndex].title, 'B');
    },
  );

  test(
    'workspace restore falls back to the previous tab when the active one is skipped',
    () {
      final ws = Workspace.fromJson({
        'id': 'w',
        'name': 'w',
        'tabs': [pdfJson('A'), unknownTab, pdfJson('B')],
        'currentTab': 1,
      });

      expect(ws.tabs[ws.activeTabIndex].title, 'A');
    },
  );
}
