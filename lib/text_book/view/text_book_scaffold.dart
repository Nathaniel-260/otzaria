import 'package:flutter/material.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/strategies/strategies.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';

/// Scaffold for text book viewing that uses Strategy Pattern
/// to select the appropriate view mode.
///
/// This replaces the previous if/else chains with a cleaner
/// strategy-based approach that makes adding new view modes easier.
class TextBookScaffold extends StatelessWidget {
  final List<String> content;
  final Function(OpenedTab) openBookCallback;
  final void Function(int, {String? searchText}) openLeftPaneTab;
  final void Function(String? text, int? lineIndex, int? column)?
  onSelectedTextChanged;
  final TextEditingValue searchTextController;
  final TextBookTab tab;
  final int? initialSidebarTabIndex;
  final Key? pageShapeKey; // מפתח עבור PageShapeScreen
  final GlobalKey? pageShapePrintBoundaryKey; // מפתח עבור צילום למסמך הדפסה
  final ValueNotifier<int?>? pageShapeSidebarTabNotifier;

  /// בקשה לפתיחת דיאלוג הגדרות צורת הדף מתוך PageShapeScreen (עדכון חי)
  final ValueNotifier<int>? pageShapeOpenSettingsNotifier;
  final ValueChanged<String?>? openSearch;
  final ValueChanged<int>? onSidebarTabChanged;

  const TextBookScaffold({
    super.key,
    required this.content,
    required this.openBookCallback,
    required this.openLeftPaneTab,
    this.onSelectedTextChanged,
    required this.searchTextController,
    required this.tab,
    this.initialSidebarTabIndex,
    this.pageShapeKey,
    this.pageShapePrintBoundaryKey,
    this.pageShapeSidebarTabNotifier,
    this.pageShapeOpenSettingsNotifier,
    this.openSearch,
    this.onSidebarTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextBookStateBuilder(
      builder: (context, state) {
        // Select the appropriate strategy based on current state
        final strategy = _selectStrategy(state);

        // Create configuration for the strategy
        final config = TextBookViewConfig(
          content: content,
          openBookCallback: openBookCallback,
          openLeftPaneTab: openLeftPaneTab,
          onSelectedTextChanged: onSelectedTextChanged,
          searchTextController: searchTextController,
          tab: tab,
          initialSidebarTabIndex: initialSidebarTabIndex,
          pageShapeKey: pageShapeKey,
          pageShapePrintBoundaryKey: pageShapePrintBoundaryKey,
          pageShapeSidebarTabNotifier: pageShapeSidebarTabNotifier,
          pageShapeOpenSettingsNotifier: pageShapeOpenSettingsNotifier,
          openSearch: openSearch,
          onSidebarTabChanged: onSidebarTabChanged,
        );

        // Build the view using the selected strategy
        return strategy.buildView(context, config);
      },
    );
  }

  /// בוחר את האסטרטגיה לפי מצב התצוגה שב-state.
  TextBookViewStrategy _selectStrategy(TextBookState state) {
    final mode = switch (state) {
      TextBookLoaded() => state.viewMode,
      TextBookInitial() => state.viewMode,
      _ => TextBookViewMode.combined,
    };
    return switch (mode) {
      TextBookViewMode.pageShape => PageShapeStrategyImpl(),
      TextBookViewMode.split => SplitViewStrategyImpl(),
      TextBookViewMode.combined => CombinedViewStrategyImpl(),
      TextBookViewMode.paged => PagedViewStrategyImpl(),
    };
  }
}
