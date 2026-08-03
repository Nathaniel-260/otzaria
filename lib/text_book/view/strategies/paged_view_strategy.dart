import 'package:flutter/material.dart';
import 'package:otzaria/text_book/paged/view/paged_book_screen.dart';
import 'package:otzaria/text_book/view/strategies/text_book_view_strategy.dart';

/// עמודים בגודל קבוע (A4) בשני טורים, כמו ספר מודפס.
class PagedViewStrategyImpl extends TextBookViewStrategy {
  @override
  String get displayName => 'עמודים';

  @override
  Widget buildView(BuildContext context, TextBookViewConfig config) {
    return PagedBookScreen(content: config.content);
  }
}
