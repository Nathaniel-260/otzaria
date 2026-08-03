import 'dart:async';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
// [EDITING DISABLED] import 'package:otzaria/text_book/editing/repository/local_overrides_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/text_book_view_mode.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';

/// Represents a tab that contains a text book.
///
/// It contains the book itself and a TextBookBloc that manages all the state
/// and business logic for the text book viewing experience.
class TextBookTab extends OpenedTab {
  /// The text book.
  final TextBook book;

  /// The index of the scrollable list.
  int index;

  /// The initial search text for this tab.
  final String searchText;

  /// טקסט להדגשה בלבד — לא מפעיל חלונית חיפוש.
  final String highlightText;

  /// שורה להדגשת רקע קבועה — מ-?mark deep link.
  final int? permanentHighlightLine;
  final Map<String, Map<String, bool>> searchOptions;
  final Map<int, List<String>> alternativeWords;
  final Map<String, String> spacingValues;
  final SearchMode searchMode;

  /// מרחק העריכה לחיפוש מקורב. בלעדיו fuzzy במרחק 0 מתנהג כחיפוש מדויק,
  /// ותוצאה שנפתחה מהחיפוש הגלובלי לא תימצא שוב בסרגל החיפוש שבתוך הספר.
  final int searchDistance;

  /// תת-מחרוזת להדגשה ממוקדת **רק** בסעיף שצוין. נטענת מקישור עומק
  /// (`otzaria://open/book/<id>?index=<n>&highlight=<text>`) ואינה פותחת חלונית
  /// חיפוש. אם null — אין הדגשה ממוקדת.
  final String? pinpointHighlight;

  /// אינדקס הסעיף שעליו תחול ההדגשה הממוקדת. אם null וב‑[pinpointHighlight] יש
  /// טקסט — נופלים חזרה ל‑[index] (זה המסלול של deep link, שבו פותחים בסעיף
  /// המודגש). השדה הופך משמעותי בעת שיכפול טאב או side‑by‑side, שם ה‑index
  /// הנוכחי כבר השתנה לפי הגלילה ואנחנו רוצים לשמר את הסעיף המקורי.
  final int? pinpointHighlightSectionIndex;

  /// The bloc that manages the text book state and logic.
  late final TextBookBloc bloc;

  final ItemScrollController scrollController = ItemScrollController();
  final ItemPositionsListener positionsListener =
      ItemPositionsListener.create();
  // בקרים נוספים עבור תצוגה מפוצלת או רשימות מקבילות
  final ItemScrollController auxScrollController = ItemScrollController();
  final ItemPositionsListener auxPositionsListener =
      ItemPositionsListener.create();
  final ScrollOffsetController mainOffsetController = ScrollOffsetController();
  final ScrollOffsetController auxOffsetController = ScrollOffsetController();

  /// הכותרת הנוכחית של המיקום בספר (למשל "בראשית פרק ד")
  final currentTitle = ValueNotifier<String>("");

  /// counter שמתגלגל עם כל בקשה לטוגל חלונית המפרשים מקיצור מקלדת גלובלי.
  /// המאזין הוא [SplitedViewScreen] בלבד; כל הגדלה = toggle יחיד.
  final ValueNotifier<int> toggleCommentatorsPaneNotifier = ValueNotifier<int>(
    0,
  );

  /// counter שמתגלגל כשיש לפתוח את פאנל ההערות האישיות.
  /// המאזין הוא [SplitedViewScreen] בלבד; כל הגדלה = פתח על טאב הערות.
  final ValueNotifier<int> openNotesTabNotifier = ValueNotifier<int>(0);

  /// counter-ים שמתגלגלים עם בקשת ניווט מקיצור מקלדת גלובלי. המאזין הוא
  /// מסך הספר; כל הגדלה = ניווט יחיד (זהה ללחיצה על כפתור הניווט המתאים).
  final ValueNotifier<int> navPreviousSegmentNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> navNextSegmentNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> navPreviousTocNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> navNextTocNotifier = ValueNotifier<int>(0);

  List<String>? commentators;
  TextBookViewMode _lastViewMode = TextBookViewMode.combined;

  // StreamSubscription לניהול ה-listener
  StreamSubscription<TextBookState>? _stateSubscription;

  /// Creates a new instance of [TextBookTab].
  ///
  /// The [index] parameter represents the initial index of the item in the scrollable list,
  /// and the [book] parameter represents the text book.
  /// The [searchText] parameter represents the initial search text,
  /// and the [commentators] parameter represents the list of commentaries to show.
  TextBookTab({
    required this.book,
    required this.index,
    this.searchText = '',
    this.highlightText = '',
    this.permanentHighlightLine,
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    this.commentators,
    bool openLeftPane = false,
    TextBookViewMode? viewMode,
    bool isPinned = false,
    String? dedupeKey,
    this.pinpointHighlight,
    this.pinpointHighlightSectionIndex,
    @visibleForTesting TextBookBloc? blocOverride,
    // מהדורה חלופית מקבלת כותרת טאב עם שם המהדורה, להבחנה מהנוסח הממוזג.
  }) : super(
         book.versionTitle == null
             ? book.title
             : '${book.title} (${book.versionTitle})',
         isPinned: isPinned,
         dedupeKey: dedupeKey,
       ) {
    // ללא מצב מפורש — ההעדפה הגלובלית "מפרשים בצד" קובעת. צורת הדף היא העדפה
    // פר-ספר ולכן היא מגיעה תמיד מפורשות מהקורא, ולא מברירת מחדל.
    final effectiveViewMode =
        viewMode ??
        ((Settings.getValue<bool>('key-splited-view') ?? true)
            ? TextBookViewMode.split
            : TextBookViewMode.combined);

    _lastViewMode = effectiveViewMode;

    // Initialize the bloc with initial state. ב‑production תמיד נבנה bloc חדש;
    // ה‑blocOverride קיים רק לטסטים שצריכים להזריק bloc עם repository מזויף
    // ולהביא אותו ל‑Loaded בלי תשתית קבצים אמיתית.
    bloc =
        blocOverride ??
        TextBookBloc(
          repository: TextBookRepository(
            fileSystem: FileSystemData.instance,
          ),
          // [EDITING DISABLED] overridesRepository: LocalOverridesRepository(),
          initialState: TextBookInitial.named(
            book,
            index,
            openLeftPane,
            commentators ?? [],
            searchText: searchText,
            searchOptions: searchOptions,
            alternativeWords: alternativeWords,
            spacingValues: spacingValues,
            searchMode: searchMode,
            searchDistance: searchDistance,
            viewMode: effectiveViewMode,
            highlightText: highlightText,
            permanentHighlightLine: permanentHighlightLine,
            pinpointHighlightIndex:
                pinpointHighlight != null && pinpointHighlight!.isNotEmpty
                ? (pinpointHighlightSectionIndex ?? index)
                : null,
            pinpointHighlightText:
                pinpointHighlight != null && pinpointHighlight!.isNotEmpty
                ? pinpointHighlight
                : null,
          ),
          scrollController: scrollController,
          positionsListener: positionsListener,
          scrollOffsetController: mainOffsetController,
        );

    // הוספת listener לעדכון האינדקס כשה-state משתנה
    _stateSubscription = bloc.stream.listen((state) {
      if (state is TextBookLoaded && state.visibleIndices.isNotEmpty) {
        index = state.visibleIndices.first;
        _lastViewMode = state.viewMode;
        // עדכון הכותרת הנוכחית
        if (state.currentTitle != null && state.currentTitle!.isNotEmpty) {
          currentTitle.value = state.currentTitle!;
        }
      }
    });
  }

  /// Cleanup when the tab is disposed
  @override
  void dispose() {
    _stateSubscription?.cancel();
    currentTitle.dispose();
    toggleCommentatorsPaneNotifier.dispose();
    openNotesTabNotifier.dispose();
    navPreviousSegmentNotifier.dispose();
    navNextSegmentNotifier.dispose();
    navPreviousTocNotifier.dispose();
    navNextTocNotifier.dispose();
    bloc.close();
    super.dispose();
  }

  /// Creates a new instance of [TextBookTab] from a JSON map.
  ///
  /// The JSON map should have 'initalIndex', 'title', 'commentaries',
  /// and 'type' keys.
  factory TextBookTab.fromJson(Map<String, dynamic> json) {
    final bool shouldOpenLeftPane = resolveRestoredReadingLeftPaneState(json);

    // 'splitedView'/'showPageShapeView' הם הפורמט שקדם לאיחוד ל-enum — נקראים
    // כדי ששולחנות עבודה שנשמרו לפני העדכון לא יאבדו את מצב התצוגה.
    final TextBookViewMode viewMode = json['viewMode'] != null
        ? TextBookViewModeX.fromStorageKey(json['viewMode'] as String?)
        : ((json['showPageShapeView'] ?? false)
              ? TextBookViewMode.pageShape
              : ((json['splitedView'] ??
                        (Settings.getValue<bool>('key-splited-view') ?? true))
                    ? TextBookViewMode.split
                    : TextBookViewMode.combined));

    final TextBook restoredBook = json['book'] != null
        ? Book.fromJson(Map<String, dynamic>.from(json['book'])) as TextBook
        : TextBook(
            title: json['title'],
          );
    return TextBookTab(
      index: json['initalIndex'],
      book: restoredBook,
      commentators: List<String>.from(json['commentators']),
      viewMode: viewMode,
      openLeftPane: shouldOpenLeftPane,
      isPinned: json['isPinned'] ?? false,
    );
  }

  /// Converts the [TextBookTab] instance into a JSON map.
  ///
  /// The JSON map contains 'title', 'initalIndex', 'commentaries',
  /// and 'type' keys.
  @override
  Map<String, dynamic> toJson() {
    // בטאב שטרם נטען (שולחן עבודה לא-פעיל) הערכים חיים רק בשדות/ב-state
    // ההתחלתי — ברירות מחדל קבועות היו מאפסות אותם בשמירה לדיסק.
    List<String> commentators = this.commentators ?? [];
    TextBookViewMode viewMode = _lastViewMode;
    int currentIndex = index; // שמירת האינדקס הנוכחי כברירת מחדל
    // ספר ה-state כולל העשרה שנעשתה ברקע (id/מחבר/קטגוריות) — עדיף לשמירה.
    TextBook bookToSave = book;

    if (bloc.state is TextBookLoaded) {
      final loadedState = bloc.state as TextBookLoaded;
      bookToSave = loadedState.book;
      commentators = loadedState.activeCommentators;
      viewMode = loadedState.viewMode;
      // עדכון האינדקס מה-state הנטען - תמיד לוקחים את האינדקס האחרון שנראה
      if (loadedState.visibleIndices.isNotEmpty) {
        currentIndex = loadedState.visibleIndices.first;
        // עדכון גם את ה-index של הטאב עצמו כדי שישמר
        index = currentIndex;
      }
    }

    return {
      'title': title,
      'book': bookToSave.toJson(),
      'initalIndex': currentIndex,
      'commentators': commentators,
      'viewMode': viewMode.storageKey,
      'showLeftPane': bloc.state.showLeftPane,
      'isPinned': isPinned,
      'type': 'TextBookTab',
    };
  }
}
