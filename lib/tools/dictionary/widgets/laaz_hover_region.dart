import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tools/dictionary/widgets/laaz_entry_view.dart';
import 'package:otzaria/utils/text/word_at_position.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';

/// מחזיר את קבוצות הלעז להצגה בריחוף עבור [word], או רשימה ריקה כשאין
/// מה להציג (מילון לא טעון, המילה אינה תעתיק לעז, או שאין התאמה).
///
/// מילה שהיא גם ראשי תיבות או ערך ארמי מדוכאת - ריחוף אינו מאפשר בחירה,
/// ולכן עדיף לא להציג כלום; בתפריט ההקשר הלעז עדיין זמין.
List<List<LaazDictionaryEntry>> laazHoverGroupsFor(
  String? word,
  DictionaryLookupRepository repository,
) {
  if (word == null || word.isEmpty) return const [];
  if (!repository.areLaazLoaded) return const [];
  if (!repository.isLikelyLaazTranslit(word)) return const [];
  if (repository.isLaazHoverSuppressed(word)) return const [];
  return repository.findLaazMatchGroups(word);
}

/// אזור שמציג חלונית קומפקטית עם פירוש לעז של רש"י בריחוף עכבר על המילה.
///
/// עוטפים בו משטח טקסט שלם; זיהוי המילה נעשה ב-hit-test רק אחרי שהסמן נח
/// (debounce), כך שלתנועת עכבר שוטפת אין עלות. מילה בתוך קישור לחיץ מדולגת —
/// לתצוגה המקדימה של הקישור יש קדימות. אזור מקונן בתוך אזור קיים הופך שקוף.
class LaazHoverRegion extends StatefulWidget {
  const LaazHoverRegion({super.key, required this.child, this.repository});

  final Widget child;

  /// להזרקת repository בבדיקות; ברירת המחדל היא ה-singleton של האפליקציה.
  final DictionaryLookupRepository? repository;

  @override
  State<LaazHoverRegion> createState() => _LaazHoverRegionState();
}

class _LaazHoverRegionState extends State<LaazHoverRegion> {
  static const Duration _hoverDelay = Duration(milliseconds: 280);

  Timer? _hoverTimer;
  Offset? _lastPosition;
  String? _shownWord;

  DictionaryLookupRepository get _repository =>
      widget.repository ?? DictionaryLookupRepository.instance;

  void _onHover(PointerHoverEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    _lastPosition = event.position;
    _hoverTimer?.cancel();
    _hoverTimer = Timer(_hoverDelay, _evaluateHover);
  }

  void _onExit(PointerExitEvent event) {
    _hoverTimer?.cancel();
    _scheduleHideIfShown();
  }

  void _evaluateHover() {
    if (!mounted) return;
    final position = _lastPosition;
    if (position == null) return;
    final hit = wordHitAtGlobalPosition(position);
    if (hit == null || hit.isInteractive) {
      _scheduleHideIfShown();
      return;
    }
    // הסמן נשאר על המילה שכבר מוצגת — אין לפתוח מחדש (מונע הבהוב).
    if (hit.word == _shownWord) return;
    final repository = _repository;
    // טעינת מילונים רק כשהמילה נראית כתעתיק לעז — לא בכל ריחוף. גם ראשי
    // התיבות והארמית נדרשים, כי בלעדיהם אין דרך לאמת שאין התנגשות.
    if (repository.isLikelyLaazTranslit(hit.word)) {
      if (!repository.areLaazLoaded) {
        unawaited(repository.ensureLaazLoaded().catchError((_) {}));
        return;
      }
      if (!repository.areAcronymsLoaded || !repository.areAramaicLoaded) {
        unawaited(repository.ensureAcronymsLoaded().catchError((_) {}));
        unawaited(repository.ensureAramaicLoaded().catchError((_) {}));
        return;
      }
    }
    final groups = laazHoverGroupsFor(hit.word, repository);
    if (groups.isEmpty) {
      _scheduleHideIfShown();
      return;
    }
    if (LinkPreviewOverlay.hasPinnedPanel) return;
    final word = hit.word;
    LinkPreviewOverlay.showContent(
      context,
      globalPosition: position,
      hoverMode: true,
      contentBuilder: (_) => LaazHoverPreviewContent(groups: groups),
      onDismissed: () {
        if (_shownWord == word) _shownWord = null;
      },
    );
    _shownWord = word;
  }

  /// סגירה מתוזמנת רק כשהחלונית הפעילה היא שלנו — לא של תצוגת קישור.
  void _scheduleHideIfShown() {
    if (_shownWord != null) LinkPreviewOverlay.scheduleHide();
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.getElementForInheritedWidgetOfExactType<_LaazHoverScope>() !=
        null) {
      return widget.child;
    }
    return _LaazHoverScope(
      child: MouseRegion(
        opaque: false,
        onHover: _onHover,
        onExit: _onExit,
        child: widget.child,
      ),
    );
  }
}

class _LaazHoverScope extends InheritedWidget {
  const _LaazHoverScope({required super.child});

  @override
  bool updateShouldNotify(_LaazHoverScope oldWidget) => false;
}
