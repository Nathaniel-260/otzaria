import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/file/toc_parser.dart';
import 'package:otzaria/utils/text/copy_utils.dart';

void main() {
  group('CopyUtils.extractCurrentPath — גיבוי מתוך תוכן העניינים', () {
    Future<String> pathAt(String content, int index) {
      final toc = TocParser.parseEntriesFromContent(content);
      return CopyUtils.extractCurrentPath(_TocBook(toc), index);
    }

    test('דילוג מרמה 2 לרמה 4 שומר גם את הפרק וגם את הסעיף', () async {
      expect(
        await pathAt('<h1>ספר</h1>\n<h2>פרק א</h2>\n<h4>סעיף א</h4>\nטקסט', 3),
        'פרק א, סעיף א',
      );
    });

    test('מעבר לפרק חדש אינו מחזיר כותרת מהמקטע הקודם', () async {
      const content =
          '<h1>ספר</h1>\n<h3>הקדמה</h3>\n<h2>פרק א</h2>\n'
          '<h4>סעיף א</h4>\n<h2>פרק ב</h2>\n<h4>סעיף ב</h4>\nטקסט';
      expect(await pathAt(content, 6), 'פרק ב, סעיף ב');
    });

    test('ספר שמתחיל ברמה 2 אינו זקוק לכותרת שורש', () async {
      expect(await pathAt('<h2>פרק</h2>\n<h4>סעיף</h4>\nטקסט', 2), 'פרק, סעיף');
    });

    test('לפני הכותרת הראשונה אין נתיב', () async {
      expect(await pathAt('טקסט\n<h2>פרק</h2>', 0), '');
    });

    test('כמה כותרות באותה שורה בוחרות את הכותרת העמוקה', () async {
      final root = TocEntry(text: 'ספר', index: 0);
      final chapter = TocEntry(text: 'פרק', index: 0, level: 2, parent: root);
      chapter.children.add(
        TocEntry(text: 'סעיף', index: 0, level: 3, parent: chapter),
      );
      root.children.add(chapter);

      expect(
        await CopyUtils.extractCurrentPath(_TocBook([root]), 0),
        'פרק, סעיף',
      );
    });

    test('העתקה עם כותרות כוללת את כל הנתיב', () async {
      final path = await pathAt(
        '<h1>ספר</h1>\n<h2>פרק א</h2>\n<h4>סעיף א</h4>\nטקסט',
        3,
      );
      expect(
        CopyUtils.formatTextWithHeaders(
          originalText: 'טקסט',
          copyWithHeaders: 'book_and_path',
          copyHeaderFormat: 'separate_line_before',
          bookName: 'ספר',
          currentPath: path,
        ),
        'ספר, פרק א, סעיף א\nטקסט',
      );
    });
  });

  group('CopyUtils.referencePath — גזירת נתיב מ-reference של תוצאת חיפוש', () {
    test('reference שאינו פותח בשם הספר מוחזר כמות שהוא', () {
      expect(
        CopyUtils.referencePath(bookName: 'ספר א', reference: 'סימן א'),
        'סימן א',
      );
    });

    test('reference שפותח בשם הספר ופסיק — הנתיב בלבד', () {
      expect(
        CopyUtils.referencePath(
          bookName: 'עבודה זרה',
          reference: 'עבודה זרה, דף עג.',
        ),
        'דף עג.',
      );
    });

    test('reference שפותח בשם הספר בלי פסיק — השארית בלבד', () {
      expect(
        CopyUtils.referencePath(bookName: 'בראשית', reference: 'בראשית פרק ד'),
        'פרק ד',
      );
    });

    test('reference שמתחיל במילה עם קידומת שם הספר מוחזר כמות שהוא', () {
      expect(
        CopyUtils.referencePath(bookName: 'ספר', reference: 'ספרים, שער א'),
        'ספרים, שער א',
      );
    });

    test('reference שזהה לשם הספר — נתיב ריק (בלי הכפלה)', () {
      expect(
        CopyUtils.referencePath(bookName: 'ספר א', reference: 'ספר א'),
        '',
      );
    });

    test('שם ספר ריק — ה-reference מוחזר כמות שהוא', () {
      expect(
        CopyUtils.referencePath(bookName: '', reference: 'סימן א'),
        'סימן א',
      );
    });
  });

  group('CopyUtils.formatTextWithHeaders — שילוב עם הנתיב שנגזר', () {
    test('book_and_path עם נתיב ריק נופל לשם הספר בלבד', () {
      expect(
        CopyUtils.formatTextWithHeaders(
          originalText: 'טקסט',
          copyWithHeaders: 'book_and_path',
          copyHeaderFormat: 'same_line_after_brackets',
          bookName: 'ספר א',
          currentPath: '',
        ),
        'טקסט (ספר א)',
      );
    });

    test('book_and_path עם נתיב מלא מרכיב "ספר, נתיב"', () {
      expect(
        CopyUtils.formatTextWithHeaders(
          originalText: 'טקסט',
          copyWithHeaders: 'book_and_path',
          copyHeaderFormat: 'separate_line_before',
          bookName: 'עבודה זרה',
          currentPath: 'דף עג.',
        ),
        'עבודה זרה, דף עג.\nטקסט',
      );
    });
  });

  group('CopyUtils.extractCurrentPath — נתיב מעץ הכותרות', () {
    TextBook bookWithToc() {
      final root = TocEntry(text: 'רש"י על בראשית', index: 0);
      final chapterA = TocEntry(
        text: 'פרק א',
        index: 1,
        level: 2,
        parent: root,
      );
      final verseD = TocEntry(
        text: 'פסוק ד',
        index: 2,
        level: 3,
        parent: chapterA,
      );
      final chapterB = TocEntry(
        text: 'פרק ב',
        index: 5,
        level: 2,
        parent: root,
      );
      chapterA.children.add(verseD);
      root.children.addAll([chapterA, chapterB]);
      return _TocBook([root]);
    }

    test('כותרות צאצאים של השורש נכנסות לנתיב', () async {
      expect(
        await CopyUtils.extractCurrentPath(bookWithToc(), 3),
        'פרק א, פסוק ד',
      );
    });

    test('כותרת עמוקה של פרק קודם לא נכנסת לפרק הבא', () async {
      expect(await CopyUtils.extractCurrentPath(bookWithToc(), 6), 'פרק ב');
    });

    test('דילוג ברמות בעץ מקובץ לא משבש את סדר הכותרות', () async {
      final book = _TocBook(
        TocParser.parseEntriesFromContent(
          '<h1>ספר</h1>\n<h2>פרק א</h2>\n<h3>הלכה א</h3>\nטקסט\n'
          'טקסט\n<h2>פרק ב</h2>\n<h4>סעיף א</h4>\nטקסט',
        ),
      );
      expect(await CopyUtils.extractCurrentPath(book, 5), 'פרק ב');
      expect(await CopyUtils.extractCurrentPath(book, 7), 'פרק ב, סעיף א');
    });

    test('הנתיב נשאר נכון גם כש-parentId במסד מצביע למקטע קודם', () async {
      final root = TocEntry(text: 'ספר', index: 0);
      final introduction = TocEntry(
        text: 'הקדמה',
        index: 1,
        level: 3,
        parent: root,
      );
      introduction.children.add(
        TocEntry(text: 'סעיף', index: 5, level: 4, parent: introduction),
      );
      root.children.addAll([
        introduction,
        TocEntry(text: 'פרק ב', index: 4, level: 2, parent: root),
      ]);

      expect(
        await CopyUtils.extractCurrentPath(_TocBook([root]), 6),
        'פרק ב, סעיף',
      );
    });
  });

  group('CopyUtils.extractCurrentPath — נתיב מתוך התוכן', () {
    test('כותרת עמוקה של הלכה קודמת לא נכנסת להלכה הבאה', () async {
      final content = [
        '<h2>פרק א</h2>',
        '<h3>הלכה א</h3>',
        '<h4>סעיף א</h4>',
        'טקסט',
        '<h3>הלכה ב</h3>',
        'טקסט של הלכה ב',
      ];
      expect(
        await CopyUtils.extractCurrentPath(
          _TocBook(const []),
          5,
          bookContent: content,
        ),
        'פרק א, הלכה ב',
      );
    });

    test('כמה כותרות באותה שורה נאספות כולן', () async {
      expect(
        await CopyUtils.extractCurrentPath(
          _TocBook(const []),
          1,
          bookContent: ['<h2>פרק א</h2><h3>הלכה א</h3>', 'טקסט'],
        ),
        'פרק א, הלכה א',
      );
    });

    test('תוכן טעון חלקית לא מחסיר כותרות שלא נטענו', () async {
      const full = [
        '<h1>ספר</h1>',
        '<h2>הלכות שבת</h2>',
        'טקסט',
        '<h3>פרק כ</h3>',
        'טקסט נבחר',
      ];
      final book = _TocBook(TocParser.parseEntriesFromContent(full.join('\n')));
      // השורות שמחוץ לחלון הטעון הן placeholders ריקים.
      const partial = ['', '', '', '<h3>פרק כ</h3>', 'טקסט נבחר'];
      expect(
        await CopyUtils.extractCurrentPath(book, 4, bookContent: partial),
        'הלכות שבת, פרק כ',
      );
    });
  });
}

class _TocBook extends TextBook {
  _TocBook(this._toc) : super(title: 'ספר');

  final List<TocEntry> _toc;

  @override
  Future<List<TocEntry>> get tableOfContents async => _toc;
}
