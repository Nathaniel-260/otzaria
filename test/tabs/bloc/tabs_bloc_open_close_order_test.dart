import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

import '../../helpers/memory_settings_cache.dart';

/// תוסף שפותח ספר ואז סוגר את עצמו (#2190): רגע בלי טאבים מעביר את מסך
/// העיון לספרייה, אף שספר נפתח.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TabsBloc bloc;
  late Directory tempDir;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    tempDir = await Directory.systemTemp.createTemp('tabs_open_close_order');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>('tabs');
    bloc = TabsBloc(repository: TabsRepository());
  });

  tearDown(() async {
    await bloc.close();
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('סגירת התוסף אחרי פתיחת ספר אינה משאירה רגע בלי טאבים', () async {
    final plugin = ToolTab(toolId: 'com.example.plugin', title: 'תוסף');
    bloc.add(AddTab(plugin));
    await bloc.stream.firstWhere((state) => state.tabs.length == 1);

    final emitted = <TabsState>[];
    final subscription = bloc.stream.listen(emitted.add);
    addTearDown(subscription.cancel);

    final book = TextBookTab(book: TextBook(title: 'בראשית'), index: 0);
    bloc.add(OpenOrFocusTab(book));
    bloc.add(RemoveTab(plugin));
    await bloc.stream
        .firstWhere(
          (state) => state.tabs.length == 1 && state.tabs.single == book,
        )
        .timeout(const Duration(seconds: 5));

    expect(
      emitted.where((state) => !state.hasOpenTabs),
      isEmpty,
      reason: 'מצב ריק מפעיל את המעבר לספרייה במסך העיון',
    );
  });
}
