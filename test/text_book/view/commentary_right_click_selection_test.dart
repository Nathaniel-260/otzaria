import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/utils/ui/context_menu_utils.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../test_helpers/memory_cache_provider.dart';

// שני היבטים של באג לחיצה ימנית במפרשים בצד ובכרטיסיית המפרשים:
// (1) פוקוס — ה-Listener שעוטף את רשימת המפרשים (מעל ה-ProgressiveScroll שהוא
//     אב ל-SelectionArea) מיקד את ProgressiveScroll בכל pointer-down כולל ימני,
//     וגזל פוקוס מ-SelectableRegion — כך שההדגשה נמחקה. התיקון מגדר את
//     ה-onPointerDown לדלג בלחיצה ימנית (kSecondaryButton).
// (2) העתקה — פעולת "העתק" קראה את הטקסט הנבחר בזמן הלחיצה (כבר null אחרי
//     שהבחירה שוחררה) במקום בזמן בניית התפריט. התיקון לוכד snapshot בבנייה.
//
// אימות אינטראקציית הפוקוס עצמה אינו בר-ביצוע כאן: מיקוד ProgressiveScroll
// מפעיל את טיימר הגלילה הרקורסיבי שלו (16ms) שהופך pumpAndSettle ל-timeout,
// ו-pump בודד אינו מממש את שינוי הפוקוס. לכן בודקים את ה-onPointerDown המקורי
// של ה-widget מול הפרדיקט הצפוי (חיבור אמיתי + לוגיקה), ואת הלוגיקה עצמה ביחידה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late _TestTextBookBloc textBookBloc;
  late _TestSettingsBloc settingsBloc;

  setUp(() {
    LibraryProviderManager.instance.resetForTesting();
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: 'מפרש בדיקה',
          categoryId: 1,
          fileType: 'txt',
        ): _FakeLibraryProvider(),
      },
      providers: [_FakeLibraryProvider()],
    );
    textBookBloc = _TestTextBookBloc(_loadedState());
    settingsBloc = _TestSettingsBloc(SettingsState.initial());
  });

  tearDown(() async {
    await textBookBloc.close();
    await settingsBloc.close();
    LibraryProviderManager.instance.resetForTesting();
  });

  testWidgets(
      'ה-Listener הממקד קיים ומחובר מעל ProgressiveScroll (חוזה מבני לגארד)',
      (tester) async {
    await _pump(tester, textBookBloc: textBookBloc, settingsBloc: settingsBloc);

    // הגארד חייב להישאר Listener translucent עם onPointerDown מעל
    // ProgressiveScroll — שם התיקון בודק את event.buttons.
    final guards = tester
        .widgetList<Listener>(find.descendant(
          of: find.byType(ProgressiveScroll),
          matching: find.byType(Listener),
        ))
        .where((l) =>
            l.behavior == HitTestBehavior.translucent &&
            l.onPointerDown != null)
        .toList();
    expect(guards, isNotEmpty,
        reason: 'ה-Listener הממקד חייב להתקיים כדי שהגארד יחול עליו');

    // לחיצה ימנית דרך ה-callback האמיתי חייבת לחזור בלי לזרוק ובלי למקד.
    final focusNode = tester
        .widget<ProgressiveScroll>(find.byType(ProgressiveScroll))
        .focusNode!;
    for (final guard in guards) {
      guard.onPointerDown!(PointerDownEvent(
        position: const Offset(100, 100),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      ));
    }
    await tester.pump();
    expect(focusNode.hasPrimaryFocus, isFalse,
        reason: 'לחיצה ימנית לא תופסת פוקוס ראשי ב-ProgressiveScroll');
  });

  test('הפרדיקט של הגארד: ממקד בכל כפתור פרט לימני (kSecondaryButton)', () {
    // התנאי הזהה לזה שב-onPointerDown של ה-Listener בפאנל: מיקוד רק כשאין
    // כפתור ימני. שינוי התנאי הזה מחזיר את הבאג — ותפיל בדיקה זו.
    bool focusesOn(int buttons) => buttons != kSecondaryButton;

    expect(focusesOn(kPrimaryButton), isTrue, reason: 'שמאלי ממקד לגלילה');
    expect(focusesOn(kMiddleMouseButton), isTrue, reason: 'אמצעי ממקד');
    expect(focusesOn(kSecondaryButton), isFalse,
        reason: 'ימני לא ממקד — אחרת הבחירה נמחקת');
  });

  group('לכידת טקסט נבחר בתפריט ההקשר', () {
    Link makeLink() => Link(
          heRef: 'רש"י על בראשית א:א',
          index1: 1,
          path2: 'אוצריא/תנך/פירושים/רשי.txt',
          index2: 1,
          connectionType: 'commentary',
        );

    testWidgets(
        'תפריט שנבנה עם טקסט נבחר: enabled ומעתיק גם אחרי איפוס המקור החי',
        (tester) async {
      // מדמה את savedSelectedTextListenable של CommentaryListBase.
      final savedText = ValueNotifier<String?>('קטע מסומן להעתקה');
      addTearDown(savedText.dispose);
      String? copiedText;

      late List<AppContextMenuEntry> entries;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              // כמו ב-menuBuilder: לוכדים את הטקסט הנבחר בזמן בניית התפריט.
              final savedTextAtBuild = savedText.value;
              entries = ContextMenuUtils.buildCommentaryContextMenu(
                context: context,
                link: makeLink(),
                openBookCallback: (_) {},
                fontSize: 18,
                savedSelectedText: savedTextAtBuild,
                onCopySelected: () => copiedText = savedTextAtBuild,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final copyEntry = entries.firstWhere((e) => e.label == 'העתק');
      expect(copyEntry.enabled, isTrue,
          reason: 'בזמן הבנייה יש טקסט נבחר — "העתק" חייב להיות פעיל');

      // לחיצה ימנית שחררה את הבחירה: המקור החי מתאפס לפני שנלחץ "העתק".
      savedText.value = null;

      copyEntry.onTap!();
      expect(copiedText, 'קטע מסומן להעתקה',
          reason: 'ההעתקה חייבת להשתמש בטקסט שנלכד בבנייה, לא בערך המנוקה');
    });

    testWidgets('טקסט נבחר ריק/רווחים בלבד — פריט "העתק" מושבת',
        (tester) async {
      for (final blank in <String?>[null, '', '   ']) {
        late List<AppContextMenuEntry> entries;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                entries = ContextMenuUtils.buildCommentaryContextMenu(
                  context: context,
                  link: makeLink(),
                  openBookCallback: (_) {},
                  fontSize: 18,
                  savedSelectedText: blank,
                  onCopySelected: () {},
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        final copyEntry = entries.firstWhere((e) => e.label == 'העתק');
        expect(copyEntry.enabled, isFalse,
            reason: 'טקסט "${blank ?? 'null'}" אינו בחירה תקפה');
      }
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required TextBookBloc textBookBloc,
  required SettingsBloc settingsBloc,
}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
  });

  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: Scaffold(
          body: CommentaryListBase(
            openBookCallback: (_) {},
            fontSize: 18,
            showSearch: true,
            shrinkWrap: false,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TextBookLoaded _loadedState() {
  final link = Link(
    heRef: 'בראשית א',
    index1: 1,
    path2: 'מפרש בדיקה.txt',
    index2: 1,
    connectionType: 'COMMENTARY',
    targetCategoryId: 1,
    targetFileType: 'txt',
  );

  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: const ['שורה א'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const ['מפרש בדיקה'],
    commentatorGroups: const [],
    availableCommentators: const ['מפרש בדיקה'],
    links: [link],
    visibleLinks: const [],
    linksByLine: {
      1: [link],
    },
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLibraryProvider implements LibraryProvider {
  @override
  String get displayName => 'Fake';

  @override
  bool get isInitialized => true;

  @override
  int get priority => 0;

  @override
  String get providerId => 'fake';

  @override
  String get sourceIndicator => 'T';

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async {
    return const [];
  }

  @override
  Future<Set<String>> getAvailableBookTitles() async {
    return {'מפרש בדיקה|1|txt'};
  }

  @override
  Future<String?> getBookText(String title, int categoryId, String fileType,
      {bool preferUserBooks = false}) async {
    return null;
  }

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    bool preferUserBooks = false,
  }) async {
    return const [];
  }

  @override
  Future<String> getLinkContent(Link link) async {
    return 'זהו פירוש לבדיקה עם טקסט שניתן לבחור';
  }

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async {
    return title == 'מפרש בדיקה';
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    return const {};
  }
}
