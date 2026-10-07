import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/external_link_repository.dart';
import 'package:otzaria/attached_libraries/view/external_link_index_tile.dart';

class _FakeLinks extends ExternalLinkRepository {
  final calls = <String>[];

  @override
  void cancelBuild() => calls.add('cancel');

  @override
  void requestResume(String slug) => calls.add('resume:$slug');

  @override
  void requestRebuild(String slug) => calls.add('rebuild:$slug');
}

AttachedLibrary _library({
  AttachedLibraryStatus status = AttachedLibraryStatus.ok,
  Set<AttachedLibraryCapability> capabilities = const {
    AttachedLibraryCapability.externalLinks,
  },
}) => AttachedLibrary(
  slug: 'dbA',
  displayName: 'dbA',
  path: 'C:/dbs/dbA.db',
  mode: AttachedLibraryMode.link,
  status: status,
  hidden: false,
  bookCount: 1,
  capabilities: capabilities,
  addedAt: DateTime(2026),
);

void main() {
  late _FakeLinks links;

  setUp(() => links = _FakeLinks());

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: ExternalLinkIndexTile(links: links),
        ),
      ),
    ),
  );

  test('השורה מוצגת רק למסד תקין עם קישורים חיצוניים', () {
    expect(hasExternalLinkLibrary([_library()]), isTrue);
    expect(hasExternalLinkLibrary(const []), isFalse);
    expect(
      hasExternalLinkLibrary([_library(status: AttachedLibraryStatus.invalid)]),
      isFalse,
    );
    expect(
      hasExternalLinkLibrary([
        _library(capabilities: const {AttachedLibraryCapability.toc}),
      ]),
      isFalse,
    );
  });

  testWidgets('מעודכן כשאין בנייה', (tester) async {
    await pump(tester);
    expect(find.text('אינדקס קישורים'), findsOneWidget);
    expect(find.text('האינדקס מעודכן'), findsOneWidget);
    expect(find.text('עצור'), findsNothing);
  });

  testWidgets('בזמן בנייה: התקדמות עם מפרידי אלפים וכפתור עצור', (
    tester,
  ) async {
    await pump(tester);
    links.buildProgress.value = const {
      'dbA': ExternalLinkBuildProgress(done: 1520000, total: 2167384),
    };
    await tester.pump();
    expect(find.text('התקדמות האינדקס: 1,520,000/2,167,384'), findsOneWidget);
    expect(find.text('האינדקס מעודכן'), findsNothing);
    expect(find.text('עצור'), findsOneWidget);
  });

  testWidgets('עצירה: ביטול בדיאלוג אינו קורא ל-API, אישור כן', (tester) async {
    await pump(tester);
    links.buildProgress.value = const {
      'dbA': ExternalLinkBuildProgress(done: 1, total: 2),
    };
    await tester.pump();

    await tester.tap(find.text('עצור'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ההתקדמות נשמרת'), findsOneWidget);
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();
    expect(links.calls, isEmpty);

    await tester.tap(find.text('עצור'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('עצור').last);
    await tester.pumpAndSettle();
    expect(links.calls, ['cancel']);
  });

  group('לא הושלם', () {
    setUp(() => links.incompleteSlugs.value = {'dbA', 'dbB'});

    testWidgets('המשך בנייה קורא ל-API בלי דיאלוג', (tester) async {
      await pump(tester);
      expect(find.text('אינדקס הקישורים לא הושלם'), findsOneWidget);
      await tester.tap(find.text('המשך בנייה'));
      await tester.pumpAndSettle();
      expect(links.calls, ['resume:dbA', 'resume:dbB']);
    });

    testWidgets('בנה מחדש: ביטול אינו קורא ל-API, אישור כן', (tester) async {
      await pump(tester);
      await tester.tap(find.text('בנה מחדש'));
      await tester.pumpAndSettle();
      expect(find.textContaining('בנייה מחדש מוחקת'), findsOneWidget);
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      expect(links.calls, isEmpty);

      await tester.tap(find.text('בנה מחדש'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('בנה מחדש').last);
      await tester.pumpAndSettle();
      expect(links.calls, ['rebuild:dbA', 'rebuild:dbB']);
    });
  });
}
