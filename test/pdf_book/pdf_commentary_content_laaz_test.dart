// גארד: מחיקת ה-LaazHoverRegion מ-build של PdfCommentaryContent תשתיק את
// ריחוף לעזי רש"י בחלונית המפרשים של ה-PDF בלי שאף בדיקה אחרת תיכשל.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_content.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tools/dictionary/widgets/laaz_hover_region.dart';
import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('LaazHoverRegion עוטף את תוכן המפרש ב-PDF', (tester) async {
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    addTearDown(() async => settingsBloc.close());

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: Scaffold(
            body: PdfCommentaryContent(
              link: Link(
                heRef: 'רש"י על בראשית א:א',
                index1: 1,
                path2: 'אוצריא/תנך/פירושים/רשי.txt',
                index2: 1,
                connectionType: 'commentary',
              ),
              fontSize: 18,
              openBookCallback: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(
      find.descendant(
        of: find.byType(PdfCommentaryContent),
        matching: find.byType(LaazHoverRegion),
      ),
      findsOneWidget,
      reason: 'בלי LaazHoverRegion אין ריחוף לעז בחלונית המפרשים של ה-PDF',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
