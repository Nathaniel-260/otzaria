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

  PagedSectionSpanBuilder? _spans;
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

    _spans = PagedSectionSpanBuilder(
      content: content,
      settings: settings,
      baseStyle: _baseStyle(settings),
    );

    _ensureLayout(bookState, geometry, settings, content);

    return BlocBuilder<PagedLayoutCubit, PagedLayoutState>(
      builder: (context, layoutState) => switch (layoutState) {
        PagedLayoutReady(book: final book) => _buildPages(
          context,
          book,
          geometry,
          bookState,
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
    BoxConstraints constraints,
  ) {
    if (book.isEmpty) {
      return const Center(child: Text('אין תוכן להצגה'));
    }

    final spans = _spans!;
    final perRow = _pagesPerRow(geometry, constraints.maxWidth);
    final rowWidth = geometry.width * perRow + (perRow > 1 ? _spreadGap : 0);
    final scale = math.min(1.0, constraints.maxWidth / (rowWidth + 24));
    final rowCount = (book.pageCount + perRow - 1) ~/ perRow;

    _scrollToSelectionAfterFrame(book, bookState, perRow);

    return SelectionArea(
      child: ScrollablePositionedList.builder(
        itemScrollController: _pageScrollController,
        itemPositionsListener: _pagePositions,
        itemCount: rowCount,
        padding: const EdgeInsets.symmetric(vertical: 12),
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
                textAlign: TextAlign.justify,
                selectedIndices: bookState.selectedIndices,
                onLineTap: _onLineTap,
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Center(
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topCenter,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: pages,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  int _pagesPerRow(PageGeometry geometry, double availableWidth) {
    if (!widget.spread) return 1;
    return availableWidth >= geometry.width * 2 + _spreadGap ? 2 : 1;
  }

  TextStyle _baseStyle(RenderSettings settings) => TextStyle(
    fontSize: settings.fontSize,
    fontFamily: settings.fontFamily,
    fontWeight: settings.fontWeight,
    height: settings.lineHeight,
  );

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
    final family = settings.fontFamily;
    if (family != null && family.isNotEmpty) {
      // גופן מערכת שלא נטען עדיין נמדד בגופן חלופי, וכל העימוד יוצא שגוי.
      unawaited(AppFonts.ensureFontLoaded(family));
    }

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
