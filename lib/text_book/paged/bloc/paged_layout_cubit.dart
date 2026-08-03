import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/text_book/paged/bloc/paged_layout_state.dart';
import 'package:otzaria/text_book/paged/models/page_geometry.dart';
import 'package:otzaria/text_book/paged/models/paged_layout_signature.dart';
import 'package:otzaria/text_book/paged/repository/paged_layout_cache.dart';
import 'package:otzaria/text_book/paged/services/paged_text_measurer.dart';
import 'package:otzaria/text_book/paged/services/pagination_engine.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

/// כמה זמן העימוד רץ ברציפות לפני שהוא מחזיר את התור לציור.
///
/// אחרי כל פרוסה ממתינים לסוף הפריים הבא (~16ms), ולכן פרוסה של 32ms נותנת
/// כשני שלישים מהזמן לעימוד ועדיין מציירת פס התקדמות שזז.
const Duration kPaginationSliceBudget = Duration(milliseconds: 32);

/// כל מה שדרוש כדי לעמד ספר.
@immutable
class PagedLayoutRequest {
  final String bookId;
  final List<String> content;

  /// האם כל שורות הספר טעונות. תוכן חלקי מגיע כמקומות שמורים ריקים, ועימוד
  /// עליו אינו תקף.
  final bool contentIsComplete;

  final PageGeometry geometry;
  final RenderSettings settings;
  final TextScaler textScaler;
  final Locale locale;

  /// בונה את הספאן של סעיף — אותו ספאן שהתצוגה תצייר.
  final InlineSpan? Function(int index) buildSpan;

  final bool Function(int index) isHeading;

  const PagedLayoutRequest({
    required this.bookId,
    required this.content,
    required this.contentIsComplete,
    required this.geometry,
    required this.settings,
    required this.textScaler,
    required this.locale,
    required this.buildSpan,
    required this.isHeading,
  });
}

/// מנהל את העימוד של ספר אחד: מטמון קודם, ואם אין — עימוד מדורג.
///
/// העימוד רץ על ה-UI thread כי מדידת טקסט אפשרית רק שם, ולכן הוא נחתך
/// לפרוסות של [kPaginationSliceBudget] עם המתנה לפריים ביניהן.
class PagedLayoutCubit extends Cubit<PagedLayoutState> {
  PagedLayoutCubit({
    PagedLayoutCache? cache,
    this._sliceBudget = kPaginationSliceBudget,
    Future<void> Function()? yieldToFrame,
  }) : _cache = cache ?? PagedLayoutCache.shared,
       _yieldToFrame = yieldToFrame ?? _defaultYield,
       super(const PagedLayoutIdle());

  static Future<void> _defaultYield() => SchedulerBinding.instance.endOfFrame;

  final PagedLayoutCache _cache;
  final Duration _sliceBudget;
  final Future<void> Function() _yieldToFrame;

  PagedLayoutSignature? _signature;

  /// עולה בכל בקשה. ריצה שנעקפה בודקת אותו אחרי כל await ונוטשת.
  int _generation = 0;

  /// החתימה של העימוד המוצג, או null כשאין.
  PagedLayoutSignature? get signature => _signature;

  Future<void> request(PagedLayoutRequest request) async {
    final generation = ++_generation;

    if (!request.contentIsComplete) {
      _signature = null;
      emit(const PagedLayoutWaitingForContent());
      return;
    }

    final signature = PagedLayoutSignature.from(
      bookId: request.bookId,
      content: request.content,
      geometry: request.geometry,
      settings: request.settings,
      textScaler: request.textScaler,
      locale: request.locale,
    );
    if (signature == _signature && state is PagedLayoutReady) return;
    _signature = signature;

    // התצוגה הקיימת שייכת לחתימה אחרת ואינה תקפה יותר.
    emit(const PagedLayoutRunning(0));

    final cached = await _cache.load(signature);
    if (_stale(generation)) return;
    if (cached != null) {
      emit(PagedLayoutReady(cached, fromCache: true));
      return;
    }

    final engine = PaginationEngine(
      geometry: request.geometry,
      measurer: PagedTextMeasurer(
        width: request.geometry.columnWidth,
        textScaler: request.textScaler,
        locale: request.locale,
        textAlign: request.settings.justifyText
            ? TextAlign.justify
            : TextAlign.start,
      ),
      sectionCount: request.content.length,
      buildSpan: request.buildSpan,
      isHeading: request.isHeading,
    );

    final budget = _sliceBudget.inMicroseconds;
    while (true) {
      final slice = Stopwatch()..start();
      engine.run(shouldStop: () => slice.elapsedMicroseconds >= budget);
      if (_stale(generation)) return;
      if (engine.isDone) break;

      emit(PagedLayoutRunning(engine.progress));
      await _yieldToFrame();
      if (_stale(generation)) return;
    }

    final book = engine.snapshot();
    emit(PagedLayoutReady(book, fromCache: false));
    unawaited(_cache.save(signature, book));
  }

  /// שוכח את העימוד המוצג, כך שהבקשה הבאה תחשב אותו מחדש.
  void reset() {
    _generation++;
    _signature = null;
    emit(const PagedLayoutIdle());
  }

  bool _stale(int generation) => isClosed || generation != _generation;
}
