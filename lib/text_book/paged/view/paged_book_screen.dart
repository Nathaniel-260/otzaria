import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/paged/bloc/paged_layout_cubit.dart';
import 'package:otzaria/text_book/paged/bloc/paged_layout_state.dart';
import 'package:otzaria/text_book/paged/models/page_geometry.dart';
import 'package:otzaria/text_book/paged/models/paginated_book.dart';
import 'package:otzaria/text_book/paged/services/paged_text_measurer.dart';
import 'package:otzaria/text_book/paged/view/paged_page_view.dart';
import 'package:otzaria/text_book/paged/view/paged_section_spans.dart';
import 'package:otzaria/text_book/utils/link_processing.dart'
    show splitContentLines;
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// מתחת לרוחב הזה עמוד בשני טורים היה מוצג בהקטנה שהופכת את הטקסט לקטן מדי,
/// ולכן העמוד שומר על גודלו ומפסיק להתפצל.
double get _minWidthForTwoColumns => PagePaperSize.a4.widthPx;

/// המרווח בין שני עמודים בתצוגת כרך פתוח.
const double _spreadGap = 16;

/// המרווח סביב העמוד. נכנס לחישוב ההתאמה לרוחב, כדי שהעמוד לא ייגע בקצה.
const double _pageMargin = 12;

/// תצוגת עמודים בגודל קבוע.
///
/// התצוגה מחזיקה את תוכן הספר המלא בעצמה: העימוד חייב לרוץ על כל השורות, ותוכן
/// שנטען בחלונות היה נותן מספר עמודים שגוי. התוכן שנטען נשלח גם ל-bloc, כדי
/// שקישורים ותוכן העניינים יעבדו על אותו ספר שלם.
class PagedBookScreen extends StatefulWidget {
  final List<String> content;
  final PagedLayoutCubit? cubitOverride;

  /// האם להציג שני עמודים זה לצד זה כשיש מקום.
  final bool spread;

  const PagedBookScreen({
    super.key,
    required this.content,
    this.cubitOverride,
    this.spread = false,
  });

  @override
  State<PagedBookScreen> createState() => _PagedBookScreenState();
}

class _PagedBookScreenState extends State<PagedBookScreen> {
  late final PagedLayoutCubit _cubit =
      widget.cubitOverride ?? PagedLayoutCubit();
  final ItemScrollController _pageScrollController = ItemScrollController();
  final ItemPositionsListener _pagePositions = ItemPositionsListener.create();

  /// גלילה אופקית, לזום שמרחיב את העמוד מעל רוחב החלון.
  final ScrollController _horizontalController = ScrollController();

  PagedSectionSpanBuilder? _spans;
  List<String>? _spansContent;
  RenderSettings? _spansSettings;
  TextStyle? _spansStyle;

  String? _requestedFont;

  List<String>? _fullContent;
  Future<void>? _loadingFullContent;

  /// העמוד שאליו כבר גללנו בעקבות [TextBookLoaded.selectedIndex].
  int? _syncedSelection;

  @override
  void initState() {
    super.initState();
    _pagePositions.itemPositions.addListener(_onVisiblePagesChanged);
  }

  @override
  void dispose() {
    _pagePositions.itemPositions.removeListener(_onVisiblePagesChanged);
    _horizontalController.dispose();
    if (widget.cubitOverride == null) _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PagedLayoutCubit>.value(
      value: _cubit,
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) {
          return BlocBuilder<TextBookBloc, TextBookState>(
            builder: (context, bookState) {
              if (bookState is! TextBookLoaded) {
                return const Center(child: CircularProgressIndicator());
              }
              return LayoutBuilder(
                builder: (context, constraints) => _buildBody(
                  context,
                  bookState,
                  settingsState,
                  constraints,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    TextBookLoaded bookState,
    SettingsState settingsState,
    BoxConstraints constraints,
  ) {
    final columns = constraints.maxWidth >= _minWidthForTwoColumns ? 2 : 1;
    final geometry = PageGeometry.paper(PagePaperSize.a4, columns: columns);
    final settings = _renderSettings(bookState, settingsState);
    final content = _fullContent ?? bookState.content;

    _spans = _spanBuilderFor(
      content,
      settings,
      PagedSectionSpanBuilder.baseStyleFor(
        settings,
        Theme.of(context).colorScheme,
      ),
    );

    _ensureLayout(bookState, geometry, settings, content);

    return BlocBuilder<PagedLayoutCubit, PagedLayoutState>(
      builder: (context, layoutState) => switch (layoutState) {
        PagedLayoutReady(book: final book) => _buildPages(
          context,
          book,
          geometry,
          bookState,
          settings,
          constraints,
        ),
        PagedLayoutRunning(progress: final progress) => _buildProgress(
          context,
          progress,
        ),
        _ => _buildProgress(context, null),
      },
    );
  }

  Widget _buildProgress(BuildContext context, double? progress) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            child: LinearProgressIndicator(value: progress),
          ),
          const SizedBox(height: 12),
          Text(
            'מחשב את עמודי הספר…',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildPages(
    BuildContext context,
    PaginatedBook book,
    PageGeometry geometry,
    TextBookLoaded bookState,
    RenderSettings settings,
    BoxConstraints constraints,
  ) {
    if (book.isEmpty) {
      return const Center(child: Text('אין תוכן להצגה'));
    }

    final spans = _spans!;
    final measurer = PagedTextMeasurer.forGeometry(
      geometry: geometry,
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.localeOf(context),
      justifyText: settings.justifyText,
    );
    final perRow = _pagesPerRow(geometry, constraints.maxWidth);
    final rowWidth = geometry.width * perRow + (perRow > 1 ? _spreadGap : 0);

    // הזום מוכפל בהתאמה לרוחב: זום 1 הוא "עמוד מלא בחלון", והגדלה משם מרחיבה
    // את העמוד ומפעילה גלילה אופקית — האותיות מוטבעות בעמוד ואינן גדלות לבדן.
    final fitScale = math.min(
      1.0,
      constraints.maxWidth / (rowWidth + _pageMargin * 2),
    );
    final scale = fitScale * bookState.pagedZoom;
    final scaledWidth = rowWidth * scale;
    final scaledHeight = geometry.height * scale;
    final viewportWidth = math.max(
      constraints.maxWidth,
      scaledWidth + _pageMargin * 2,
    );
    final rowCount = (book.pageCount + perRow - 1) ~/ perRow;

    _scrollToSelectionAfterFrame(book, bookState, perRow);

    return SelectionArea(
      child: Scrollbar(
        controller: _horizontalController,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        child: SingleChildScrollView(
          controller: _horizontalController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: viewportWidth,
            child: ScrollablePositionedList.builder(
              itemScrollController: _pageScrollController,
              itemPositionsListener: _pagePositions,
              itemCount: rowCount,
              padding: const EdgeInsets.symmetric(vertical: _pageMargin),
              itemBuilder: (context, rowIndex) {
                final pages = <Widget>[];
                for (var offset = 0; offset < perRow; offset++) {
                  final pageIndex = rowIndex * perRow + offset;
                  if (pageIndex >= book.pageCount) break;
                  if (offset > 0) pages.add(const SizedBox(width: _spreadGap));
                  pages.add(
                    PagedPageView(
                      page: book.pages[pageIndex],
                      geometry: geometry,
                      spans: spans,
                      measurer: measurer,
                      selectedIndices: bookState.selectedIndices,
                      onLineTap: _onLineTap,
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Center(
                    // ה-Transform אינו משנה את גודל הפריסה, ולכן המידות
                    // המוקטנות נקבעות כאן — אחרת העמוד תופס את גובהו המלא
                    // ומשאיר רווח ריק מתחתיו.
                    child: SizedBox(
                      width: scaledWidth,
                      height: scaledHeight,
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: rowWidth,
                          height: geometry.height,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: pages,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// טוען גופן מערכת ומרנדר מחדש כשהוא מוכן.
  ///
  /// גופן שלא נטען עדיין נמדד בגופן חלופי, וכל העימוד יוצא שגוי. הטעינה
  /// אסינכרונית ואינה משדרת שינוי, ולכן בלי ה-`setState` כאן העימוד היה נשאר
  /// זה של הגופן החלופי עד שמשהו אחר במקרה יגרום ל-build.
  void _ensureFontLoaded(String? family) {
    if (family == null || family.isEmpty || family == _requestedFont) return;
    _requestedFont = family;
    AppFonts.ensureFontLoaded(family).then((_) {
      if (mounted && _requestedFont == family) setState(() {});
    });
  }

  /// בונה הספאנים ממוזכר: `_buildBody` רץ בכל state של ה-bloc, וגם בכל פריים
  /// גלילה. בנייה מחדש הייתה מאבדת את מטמון הספאנים ומריצה עיבוד HTML מלא של
  /// כל הסעיפים הגלויים בכל פריים.
  PagedSectionSpanBuilder _spanBuilderFor(
    List<String> content,
    RenderSettings settings,
    TextStyle baseStyle,
  ) {
    final existing = _spans;
    if (existing != null &&
        identical(_spansContent, content) &&
        _spansSettings == settings &&
        _spansStyle == baseStyle) {
      return existing;
    }

    _spansContent = content;
    _spansSettings = settings;
    _spansStyle = baseStyle;
    return PagedSectionSpanBuilder(
      content: content,
      settings: settings,
      baseStyle: baseStyle,
    );
  }

  int _pagesPerRow(PageGeometry geometry, double availableWidth) {
    if (!widget.spread) return 1;
    return availableWidth >= geometry.width * 2 + _spreadGap ? 2 : 1;
  }

  RenderSettings _renderSettings(
    TextBookLoaded bookState,
    SettingsState settingsState,
  ) {
    return RenderSettings(
      removeNikud: bookState.removeNikud,
      removePunctuation: bookState.removePunctuation,
      removeTeamim: !settingsState.showTeamim,
      replaceHolyNames: settingsState.replaceHolyNames,
      searchText: bookState.searchText,
      searchOptions: bookState.searchOptions,
      alternativeWords: bookState.alternativeWords,
      spacingValues: bookState.spacingValues,
      searchMode: bookState.searchMode,
      searchDistance: bookState.searchDistance,
      fontSize: bookState.fontSize,
      fontFamily: settingsState.fontFamily,
      fontWeight: settingsState.fontBold ? FontWeight.bold : null,
      lineHeight: settingsState.lineHeight,
    );
  }

  void _ensureLayout(
    TextBookLoaded bookState,
    PageGeometry geometry,
    RenderSettings settings,
    List<String> content,
  ) {
    if (_fullContent == null) {
      _loadFullContent(bookState);
      return;
    }

    final spans = _spans!;
    _ensureFontLoaded(settings.fontFamily);

    unawaited(
      _cubit.request(
        PagedLayoutRequest(
          bookId: bookState.book.title,
          content: content,
          contentIsComplete: true,
          geometry: geometry,
          settings: settings,
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.localeOf(context),
          buildSpan: spans.spanFor,
          isHeading: spans.isHeading,
        ),
      ),
    );
  }

  void _loadFullContent(TextBookLoaded bookState) {
    if (_loadingFullContent != null) return;
    final bloc = context.read<TextBookBloc>();
    _loadingFullContent = () async {
      try {
        final raw = await bloc.repository.getBookContent(bookState.book);
        final lines = await splitContentLines(raw);
        if (!mounted) return;
        setState(() => _fullContent = lines);
        if (!bloc.isClosed) {
          bloc.add(
            ApplyFullBookContent(
              bookTitle: bookState.book.title,
              content: lines,
            ),
          );
        }
      } catch (e) {
        debugPrint('⚠️ paged view: full content load failed: $e');
        if (mounted) setState(() => _fullContent = widget.content);
      } finally {
        _loadingFullContent = null;
      }
    }();
  }

  void _onLineTap(int sourceIndex) {
    final bloc = context.read<TextBookBloc>();
    if (bloc.isClosed) return;
    final state = bloc.state;
    final alreadySelected =
        state is TextBookLoaded && state.selectedIndex == sourceIndex;
    bloc.add(UpdateSelectedIndex(alreadySelected ? null : sourceIndex));
  }

  void _onVisiblePagesChanged() {
    final positions = _pagePositions.itemPositions.value;
    if (positions.isEmpty || !mounted) return;

    final layoutState = _cubit.state;
    if (layoutState is! PagedLayoutReady) return;
    final book = layoutState.book;

    final indices = <int>{};
    for (final position in positions) {
      for (final page in _pagesOfRow(book, position.index)) {
        for (final slice in page.slices) {
          indices.add(slice.sourceIndex);
        }
      }
    }
    if (indices.isEmpty) return;

    final bloc = context.read<TextBookBloc>();
    if (bloc.isClosed) return;
    final sorted = indices.toList()..sort();
    final current = bloc.state;
    if (current is TextBookLoaded &&
        current.visibleIndices.length == sorted.length &&
        current.visibleIndices.first == sorted.first &&
        current.visibleIndices.last == sorted.last) {
      return;
    }
    bloc.add(UpdateVisibleIndecies(sorted));
  }

  /// העמודים שמופיעים בשורת-הרשימה [rowIndex]. `perRow` נגזר מאורך הרשימה
  /// שהוצגה, ולכן מחושב כאן מחדש מהמצב הנוכחי.
  Iterable<BookPage> _pagesOfRow(PaginatedBook book, int rowIndex) {
    final perRow = _lastPerRow;
    final first = rowIndex * perRow;
    return [
      for (var offset = 0; offset < perRow; offset++)
        if (first + offset < book.pageCount) book.pages[first + offset],
    ];
  }

  int _lastPerRow = 1;

  void _scrollToSelectionAfterFrame(
    PaginatedBook book,
    TextBookLoaded bookState,
    int perRow,
  ) {
    _lastPerRow = perRow;
    final selected = bookState.selectedIndex;
    if (selected == null || selected == _syncedSelection) return;
    _syncedSelection = selected;

    final row = book.pageIndexOfSource(selected) ~/ perRow;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageScrollController.isAttached) return;
      _pageScrollController.jumpTo(index: row);
    });
  }
}
