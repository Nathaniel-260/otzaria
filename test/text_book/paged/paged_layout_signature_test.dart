// טסטים לחתימת הפריסה של תצוגת העמודים.
//
// הטסט המרכזי כאן הוא ההתאמה ל-`sectionContentRenderingSignature`: שדה חדש
// ב-RenderSettings שמשפיע על פריסה חייב להיכנס לשתי החתימות. אם הוא ייכנס רק
// לאחת, הטסט נכשל — ולא נגלה בשטח שהעימוד השמור לא נפסל.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/paged/models/page_geometry.dart';
import 'package:otzaria/text_book/paged/models/paged_layout_signature.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

void main() {
  final geometry = PageGeometry.paper(PagePaperSize.a4);
  const content = ['בראשית ברא אלהים', 'את השמים ואת הארץ'];
  const locale = Locale('he', 'IL');

  PagedLayoutSignature sign({
    String bookId = 'ספר בדיקה',
    List<String> lines = content,
    PageGeometry? pageGeometry,
    RenderSettings settings = const RenderSettings(),
    TextScaler textScaler = TextScaler.noScaling,
    Locale textLocale = locale,
  }) {
    return PagedLayoutSignature.from(
      bookId: bookId,
      content: lines,
      geometry: pageGeometry ?? geometry,
      settings: settings,
      textScaler: textScaler,
      locale: textLocale,
    );
  }

  group('התאמה ל-sectionContentRenderingSignature', () {
    /// כל שדה של RenderSettings ושינוי אחד שלו.
    final mutators = <String, RenderSettings Function(RenderSettings)>{
      // משפיעים על פריסה
      'removeNikud': (s) => s.copyWith(removeNikud: !s.removeNikud),
      'removePunctuation': (s) =>
          s.copyWith(removePunctuation: !s.removePunctuation),
      'removeTeamim': (s) => s.copyWith(removeTeamim: !s.removeTeamim),
      'replaceHolyNames': (s) =>
          s.copyWith(replaceHolyNames: !s.replaceHolyNames),
      'fontSize': (s) => s.copyWith(fontSize: s.fontSize + 1),
      'fontFamily': (s) => s.copyWith(fontFamily: 'Rubik'),
      'fontWeight': (s) => s.copyWith(fontWeight: FontWeight.w700),
      'lineHeight': (s) => s.copyWith(lineHeight: s.lineHeight + 0.1),
      'enableInlineLinks': (s) =>
          s.copyWith(enableInlineLinks: !s.enableInlineLinks),
      'formatParentheses': (s) =>
          s.copyWith(formatParentheses: !s.formatParentheses),
      'justifyText': (s) => s.copyWith(justifyText: !s.justifyText),
      // לא משפיעים — מצב חיפוש רגעי
      'searchText': (s) => s.copyWith(searchText: 'ברא'),
      'currentSearchIndex': (s) => s.copyWith(currentSearchIndex: 3),
      'searchOptions': (s) => s.copyWith(
        searchOptions: const {
          'a': {'b': true},
        },
      ),
      'alternativeWords': (s) => s.copyWith(
        alternativeWords: const {
          0: ['ברא'],
        },
      ),
      'spacingValues': (s) => s.copyWith(spacingValues: const {'a': '1'}),
      'isFuzzySearch': (s) => s.copyWith(isFuzzySearch: !s.isFuzzySearch),
      'searchMode': (s) => s.copyWith(searchMode: SearchMode.fuzzy),
      'searchDistance': (s) => s.copyWith(searchDistance: 5),
      'highlightYellowBackground': (s) =>
          s.copyWith(highlightYellowBackground: !s.highlightYellowBackground),
      'partialWordHighlight': (s) =>
          s.copyWith(partialWordHighlight: !s.partialWordHighlight),
    };

    test('כיסוי מלא של שדות RenderSettings', () {
      // ההגנה על הרשימה עצמה: שדה חדש שלא נוסף כאן לא ייבדק כלל.
      const fieldCount = 21;
      expect(mutators.length, fieldCount);
    });

    test('החתימות מסכימות על כל שדה — משנה פריסה, או לא משנה בשתיהן', () {
      const base = RenderSettings();
      final baseKey = sign(settings: base).cacheKey;
      final baseContent = base.sectionContentRenderingSignature;

      for (final entry in mutators.entries) {
        final mutated = entry.value(base);
        final contentChanged =
            mutated.sectionContentRenderingSignature != baseContent;
        final keyChanged = sign(settings: mutated).cacheKey != baseKey;

        expect(
          keyChanged,
          contentChanged,
          reason:
              '${entry.key}: sectionContentRenderingSignature '
              '${contentChanged ? "השתנה" : "לא השתנה"} '
              'אבל cacheKey ${keyChanged ? "השתנה" : "לא השתנה"}',
        );
      }
    });

    test('שינוי מצב חיפוש אינו מחייב עימוד מחדש', () {
      const base = RenderSettings();
      final searching = base.copyWith(
        searchText: 'ברא',
        currentSearchIndex: 2,
        highlightYellowBackground: true,
      );

      expect(sign(settings: searching).cacheKey, sign(settings: base).cacheKey);
    });
  });

  group('זהות התוכן', () {
    test('שורה שנוספה משנה את המפתח', () {
      expect(
        sign(lines: const [...content, 'ויאמר אלהים']).cacheKey,
        isNot(sign().cacheKey),
      );
    });

    test('שינוי בתוך שורה משנה את המפתח', () {
      expect(
        sign(lines: const ['בראשית ברא אלהימ', 'את השמים ואת הארץ']).cacheKey,
        isNot(sign().cacheKey),
      );
    });

    test('החלפת סדר השורות משנה את המפתח', () {
      expect(
        sign(lines: content.reversed.toList()).cacheKey,
        isNot(sign().cacheKey),
      );
    });

    test('ספר אחר עם אותו תוכן מקבל מפתח אחר', () {
      expect(sign(bookId: 'ספר אחר').cacheKey, isNot(sign().cacheKey));
    });

    test('אותו תוכן בדיוק מקבל מפתח זהה', () {
      expect(sign(lines: [...content]).cacheKey, sign().cacheKey);
      expect(sign(lines: [...content]), sign());
    });
  });

  group('סביבת המדידה', () {
    test('זום טקסט של המערכת משנה את המפתח', () {
      expect(
        sign(textScaler: const TextScaler.linear(1.3)).cacheKey,
        isNot(sign().cacheKey),
      );
    });

    test('סקיילר לא-לינארי משנה את המפתח', () {
      // סקיילר לא-לינארי מחזיר 1.0 עבור 1.0 ובכל זאת מגדיל גדלים אמיתיים,
      // ולכן מדידה על 1.0 בלבד לא הייתה מבדילה בינו לבין סקיילר מנוטרל.
      expect(
        sign(textScaler: const _NonLinearScaler()).cacheKey,
        isNot(sign().cacheKey),
      );
    });

    test('locale אחר משנה את המפתח — הוא משפיע על shaping', () {
      expect(
        sign(textLocale: const Locale('en', 'US')).cacheKey,
        isNot(sign().cacheKey),
      );
    });

    test('גאומטריה אחרת משנה את המפתח', () {
      expect(
        sign(pageGeometry: geometry.singleColumn).cacheKey,
        isNot(sign().cacheKey),
      );
    });

    test('רישום הגופן שבשימוש כשהשתנה פוסל עימוד שנמדד לפניו', () {
      const font = 'SomeSystemFontForTest';
      const settings = RenderSettings(fontFamily: font);
      final before = sign(settings: settings).cacheKey;
      addTearDown(AppFonts.debugResetSystemFontsCache);

      AppFonts.debugMarkSeparateBoldSystemFont(font);

      expect(sign(settings: settings).cacheKey, isNot(before));
    });

    test('רישום גופן אחר אינו פוסל את העימוד', () {
      // התג הוא פר-גופן בכוונה: מונה גלובלי היה גורם לתצוגה מקדימה של גופן
      // במסך ההגדרות לבטל את העימוד השמור של כל הספרים.
      const settings = RenderSettings(fontFamily: 'FontInUse');
      final before = sign(settings: settings).cacheKey;
      addTearDown(AppFonts.debugResetSystemFontsCache);

      AppFonts.debugMarkSeparateBoldSystemFont('AnUnrelatedFont');

      expect(sign(settings: settings).cacheKey, before);
    });
  });

  test('גרסת המנוע נכללת במפתח', () {
    expect(sign().cacheKey, startsWith('v$kPagedLayoutEngineVersion|'));
  });
}

/// סקיילר שאינו מכפיל לינארית: 1.0 נשאר 1.0, וגדלים אמיתיים גדלים.
class _NonLinearScaler extends TextScaler {
  const _NonLinearScaler();

  @override
  double scale(double fontSize) => fontSize <= 1.0 ? fontSize : fontSize * 1.4;

  @override
  double get textScaleFactor => 1.0;
}
