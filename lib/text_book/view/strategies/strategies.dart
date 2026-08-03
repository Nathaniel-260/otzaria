// Text Book View Strategies
//
// This module implements the Strategy Pattern for different text book
// viewing modes. It allows easy addition of new view modes without
// modifying existing code.
//
// Available strategies:
// - [SplitViewStrategyImpl] - Shows commentaries in a side panel
// - [CombinedViewStrategyImpl] - Shows commentaries below the text
// - [PageShapeStrategyImpl] - Traditional Talmud page layout
// - [PagedViewStrategyImpl] - Fixed-size pages (A4) in two columns

export 'text_book_view_strategy.dart';
export 'split_view_strategy.dart';
export 'combined_view_strategy.dart';
export 'page_shape_strategy.dart';
export 'paged_view_strategy.dart';
