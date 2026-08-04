import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/text_book_view_mode.dart';
import 'package:otzaria/text_book/paged/models/paged_zoom.dart';
import 'package:otzaria/text_book/utils/per_book_display_settings.dart';

const double _minFontSize = 15.0;
const double _maxFontSize = 50.0;
const double _defaultFontSize = 25.0;
const double _fontSizeStep = 3.0;

/// הגדלה או הקטנה בקורא: [direction] הוא 1 להגדלה ו-1- להקטנה.
///
/// בתצוגת העמודים הזום מגדיל את העמוד עצמו ולא את הגופן. העמוד הוא בגודל
/// פיזי קבוע, ושינוי גופן בו היה מחייב עימוד מלא מחדש ומזיז טקסט בין עמודים.
Future<void> applyReaderZoom(
  BuildContext context,
  TextBookLoaded state,
  int direction,
) async {
  if (state.viewMode == TextBookViewMode.paged) {
    context.read<TextBookBloc>().add(
      UpdatePagedZoom(steppedPagedZoom(state.pagedZoom, direction)),
    );
    return;
  }

  final newSize = (state.fontSize + direction * _fontSizeStep).clamp(
    _minFontSize,
    _maxFontSize,
  );
  context.read<TextBookBloc>().add(UpdateFontSize(newSize));
  await savePerBookDisplaySettings(context, state, fontSize: newSize);
}

Future<void> readerZoomIn(BuildContext context, TextBookLoaded state) =>
    applyReaderZoom(context, state, 1);

Future<void> readerZoomOut(BuildContext context, TextBookLoaded state) =>
    applyReaderZoom(context, state, -1);

/// איפוס לברירת המחדל — גודל הגופן בתצוגות הזורמות, זום 1 בתצוגת העמודים.
Future<void> resetReaderZoom(BuildContext context, TextBookLoaded state) async {
  if (state.viewMode == TextBookViewMode.paged) {
    context.read<TextBookBloc>().add(const UpdatePagedZoom(kDefaultPagedZoom));
    return;
  }

  context.read<TextBookBloc>().add(const UpdateFontSize(_defaultFontSize));
  await savePerBookDisplaySettings(context, state, fontSize: _defaultFontSize);
}

/// התוויות של כפתורי ההגדלה/הקטנה. בתצוגת העמודים מגדילים את העמוד, ולכן
/// "גודל הטקסט" היה מתאר את הפעולה לא נכון.
String readerZoomInLabel(TextBookViewMode mode) =>
    mode == TextBookViewMode.paged ? 'הגדל את העמוד' : 'הגדל את גודל הטקסט';

String readerZoomOutLabel(TextBookViewMode mode) =>
    mode == TextBookViewMode.paged ? 'הקטן את העמוד' : 'הקטן את גודל הטקסט';
