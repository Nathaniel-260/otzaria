import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/view/full_text_facet_filtering.dart';
import 'package:otzaria/search/view/search_navigation_tree.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../helpers/memory_settings_cache.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _NoEngineRepository extends SearchRepository {
  const _NoEngineRepository();

  @override
  Stream<SearchStreamUpdate> searchTextsStreamWithCounts(
    SearchEngineRequest request, {
    int chunkSize = 50,
  }) => const Stream.empty();
}

Future<SearchBloc> _pumpFiltering(
  WidgetTester tester,
  List<String> scope,
) async {
  final searchBloc = SearchBloc(
    repository: const _NoEngineRepository(),
    initialConfiguration: SearchConfiguration(
      currentFacets: scope,
      searchScopeFacets: scope,
    ),
  );
  final library = Library(categories: []);
  final libraryBloc = _MockLibraryBloc();
  whenListen(
    libraryBloc,
    const Stream<LibraryState>.empty(),
    initialState: LibraryState(
      library: library,
      isLoading: false,
      currentCategory: library,
    ),
  );
  final settingsBloc = _MockSettingsBloc();
  whenListen(
    settingsBloc,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial(),
  );
  final tab = SearchingTab('חיפוש', null);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tab.dispose();
    await searchBloc.close();
    await libraryBloc.close();
    await settingsBloc.close();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<SearchBloc>.value(value: searchBloc),
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: SizedBox(
            width: 320,
            height: 600,
            child: SearchFacetFiltering(tab: tab),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return searchBloc;
}

SearchNavigationTree _tree(WidgetTester tester) =>
    tester.widget<SearchNavigationTree>(find.byType(SearchNavigationTree));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets(
    'עם סינון "ספרי יסוד": לחיצה על קטגוריה ואז על השורש מחזירה לכל ההיקף',
    (tester) async {
      const scope = ['/', '/base'];
      final searchBloc = await _pumpFiltering(tester, scope);

      _tree(tester).onSetFacet('/תנ"ך');
      await tester.pumpAndSettle();
      expect(searchBloc.state.currentFacets, ['/תנ"ך', '/base']);
      expect(searchBloc.state.searchScopeFacets, scope);

      _tree(tester).onSetFacet('/');
      await tester.pumpAndSettle();
      expect(searchBloc.state.currentFacets, scope);
      expect(searchBloc.state.searchScopeFacets, scope);
    },
  );

  testWidgets(
    'עם סינון ממד: ביטול הקטגוריה האחרונה בבחירה מרובה חוזר להיקף ולא לכל הספרייה',
    (tester) async {
      const scope = ['/תנ"ך', '/base'];
      final searchBloc = await _pumpFiltering(tester, scope);

      _tree(tester).onToggleFacet('/תנ"ך');
      await tester.pumpAndSettle();
      expect(searchBloc.state.currentFacets, scope);
      expect(searchBloc.state.searchScopeFacets, scope);
    },
  );
}
