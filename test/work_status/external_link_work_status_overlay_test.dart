import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/repository/external_link_repository.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/work_status/work_status_item.dart';
import 'package:otzaria/work_status/work_status_overlay.dart';

class _FakeLinks extends ExternalLinkRepository {
  final calls = <String>[];

  @override
  void pauseBuild() {
    calls.add('pause');
    buildPaused.value = true;
  }

  @override
  void resumeBuild() {
    calls.add('resume');
    buildPaused.value = false;
  }

  @override
  void setBuildEconomy(bool on) {
    calls.add('economy:$on');
    buildEconomy.value = on;
  }
}

const _booksItem = WorkStatusItem(
  id: 'indexing',
  title: 'אינדוקס ספרים',
  message: 'התוכנה בתהליך אינדוקס',
  detail: 'התקדמות: 133/1633',
  progress: 0.08,
);

const _booksCard = ValueKey('books-work-status');
const _linksCard = ValueKey('external-link-work-status');

void main() {
  late _FakeLinks links;
  late WorkStatusCubit cubit;

  setUp(() {
    links = _FakeLinks();
    cubit = WorkStatusCubit();
  });

  tearDown(() => cubit.close());

  Future<void> pump(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.windows,
  }) => tester.pumpWidget(
    BlocProvider.value(
      value: cubit,
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: Stack(children: [WorkStatusOverlay(links: links)]),
          ),
        ),
      ),
    ),
  );

  void startBuild() {
    links.buildProgress.value = const {
      'dbA': ExternalLinkBuildProgress(done: 1000000, total: 2000000),
      'dbB': ExternalLinkBuildProgress(done: 520000, total: 167384),
    };
  }

  testWidgets('מוצג בזמן בנייה עם הטקסט והמספרים ונעלם בסיום', (tester) async {
    await pump(tester);
    expect(find.byKey(_linksCard), findsNothing);

    links.buildProgress.value = const {
      'dbA': ExternalLinkBuildProgress(done: 1500000, total: 2167384),
    };
    await tester.pump();

    expect(find.text('אינדוקס קישורים'), findsOneWidget);
    expect(find.text('הקישורים בתהליך אינדוקס'), findsOneWidget);
    expect(find.text('התקדמות: 1,500,000/2,167,384'), findsOneWidget);
    expect(find.text('69%'), findsOneWidget);

    links.buildProgress.value = const {};
    await tester.pump();
    expect(find.byKey(_linksCard), findsNothing);
  });

  testWidgets('נסגר ב-X וחוזר בבנייה חדשה', (tester) async {
    await pump(tester);
    startBuild();
    await tester.pump();

    await tester.tap(
      find.descendant(
        of: find.byKey(_linksCard),
        matching: find.byTooltip('סגור'),
      ),
    );
    await tester.pump();
    expect(find.byKey(_linksCard), findsNothing);

    links.buildProgress.value = const {};
    await tester.pump();
    startBuild();
    await tester.pump();
    expect(find.byKey(_linksCard), findsOneWidget);
  });

  testWidgets('צמוד ומימין לחלון אינדוקס הספרים; לבדו תופס את מקומו', (
    tester,
  ) async {
    cubit.upsert(_booksItem);
    await pump(tester);
    startBuild();
    await tester.pump();

    final books = tester.getRect(find.byKey(_booksCard));
    final linksRect = tester.getRect(find.byKey(_linksCard));
    expect(linksRect.left, greaterThan(books.right));
    expect(linksRect.left - books.right, lessThan(24));
    expect(linksRect.bottom, books.bottom);

    cubit.remove('indexing');
    await tester.pump();
    await tester.pump();
    expect(find.byKey(_booksCard), findsNothing);
    final alone = tester.getRect(find.byKey(_linksCard));
    expect(alone.left, books.left);
  });

  testWidgets('סגירת חלון הספרים אינה סוגרת את חלון הקישורים', (tester) async {
    cubit.upsert(_booksItem);
    await pump(tester);
    startBuild();
    await tester.pump();

    await tester.tap(
      find.descendant(
        of: find.byKey(_booksCard),
        matching: find.byTooltip('סגור'),
      ),
    );
    await tester.pump();
    expect(find.byKey(_booksCard), findsNothing);
    expect(find.byKey(_linksCard), findsOneWidget);
  });

  testWidgets('השהה, המשך ומצב חסכוני קוראים ל-API', (tester) async {
    await pump(tester);
    startBuild();
    await tester.pump();

    await tester.tap(find.text('השהה'));
    await tester.pump();
    expect(links.calls, ['pause']);
    expect(find.text('האינדוקס מושהה'), findsOneWidget);

    await tester.tap(find.text('המשך'));
    await tester.pump();
    expect(links.calls, ['pause', 'resume']);
    expect(find.text('השהה'), findsOneWidget);

    await tester.tap(find.text('מצב חסכוני'));
    await tester.pump();
    expect(links.calls.last, 'economy:true');
    expect(links.buildEconomy.value, isTrue);
  });
}
