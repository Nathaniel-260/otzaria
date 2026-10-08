import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

import '../../support/search_engine_test_init.dart';

const _text = 'זהו פירוש לבדיקה עם טקסט שניתן לבחור';
const _word = 'פירוש';

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  // Flutter 3.47 מצייר את הבחירה לפני הטקסט, ולכן רקע אטום של ההדגשה מכסה אותה.
  for (final current in [-1, 0]) {
    testWidgets('בחירה על תוצאת חיפוש נראית, current=$current (issue #2198)', (
      tester,
    ) async {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: RepaintBoundary(
                key: boundaryKey,
                child: SelectionArea(
                  child: SmartTextWidget(
                    text: _text,
                    settings: RenderSettings(
                      fontSize: 20,
                      searchText: _word,
                      currentSearchIndex: current,
                      partialWordHighlight: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final paragraph = tester.renderObject<RenderParagraph>(
        find.byWidgetPredicate((w) => w is RichText),
      );
      final boundary =
          tester.renderObject(find.byKey(boundaryKey)) as RenderRepaintBoundary;
      final start = paragraph.text.toPlainText().indexOf(_word);
      final wordBox = paragraph
          .getBoxesForSelection(
            TextSelection(
              baseOffset: start,
              extentOffset: start + _word.length,
            ),
          )
          .first
          .toRect();
      // פינת התיבה ולא מרכזה — שם אין גליף, רק רקע ההדגשה או הבחירה.
      final probe = paragraph.localToGlobal(
        wordBox.topLeft + const Offset(1, 1),
        ancestor: boundary,
      );

      Future<int> pixelAtProbe() async {
        final bytes = await tester.runAsync(() async {
          final image = await boundary.toImage();
          return (await image.toByteData())!;
        });
        final width = boundary.size.width.round();
        final offset = (probe.dy.round() * width + probe.dx.round()) * 4;
        return (bytes as ByteData).getUint32(offset);
      }

      final unselected = await pixelAtProbe();
      tester
          .state<SelectionAreaState>(find.byType(SelectionArea))
          .selectableRegion
          .selectAll();
      await tester.pumpAndSettle();

      expect(paragraph.selections, isNotEmpty);
      expect(await pixelAtProbe(), isNot(unselected));
    }, skip: !engineReady);
  }
}
