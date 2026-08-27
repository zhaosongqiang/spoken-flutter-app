import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ielts_speaking/core/models.dart';
import 'package:ielts_speaking/core/navigation_data.dart';
import 'package:ielts_speaking/core/providers.dart';
import 'package:ielts_speaking/features/history_page.dart';
import 'package:ielts_speaking/features/practice_page.dart';
import 'package:ielts_speaking/features/score_detail_sheet.dart';
import 'package:ielts_speaking/router.dart';
import 'package:ielts_speaking/ui/widgets.dart';

void main() {
  testWidgets('page navigation notifies without treating dialogs as pages',
      (tester) async {
    var pageChanges = 0;

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [PageChangeObserver(() => pageChanges++)],
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      content: const Text('弹窗'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('打开弹窗'),
                ),
                TextButton(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        body: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('返回首页'),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('打开页面'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开弹窗'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(pageChanges, 0);

    await tester.tap(find.text('打开页面'));
    await tester.pumpAndSettle();
    expect(pageChanges, 1);
    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();
    expect(pageChanges, 2);
  });

  testWidgets('score details open over the source page without page navigation',
      (tester) async {
    final pendingBootstrap = Completer<AccountBootstrap>();
    var pageChanges = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountBootstrapProvider.overrideWith(
            (ref) => pendingBootstrap.future,
          ),
        ],
        child: MaterialApp(
          navigatorObservers: [PageChangeObserver(() => pageChanges++)],
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showScoreDetailSheet(
                  context: context,
                  recordId: 1,
                  detailId: 2,
                ),
                child: const Text('查看评分详情'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('查看评分详情'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('评分详情'), findsOneWidget);
    expect(find.text('正在加载评分详情…'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ScoreDetailSheet)).height,
      closeTo(
          tester.view.physicalSize.height / tester.view.devicePixelRatio * .7,
          .01),
    );
    expect(pageChanges, 0);

    await tester.tap(find.byTooltip('关闭评分详情'));
    await tester.pumpAndSettle();
    expect(find.text('查看评分详情'), findsOneWidget);
    expect(find.text('评分详情'), findsNothing);
    expect(pageChanges, 0);
  });

  testWidgets(
      'score details render passed words before AI evaluation completes',
      (tester) async {
    final pendingBootstrap = Completer<AccountBootstrap>();
    const detail = AssessmentDetail(
      id: 2,
      recordId: 1,
      questionId: 3,
      part: 1,
      seqNo: 1,
      questionPrompt: 'Say hello.',
      questionAudioUrl: '',
      audioPath: '',
      transcription: 'Hello.',
      suggestedScore: 95,
      words: [
        <String, dynamic>{
          'word': 'Hello',
          'overall': 95,
          'pause': true,
          'link': <String, dynamic>{'linkable': 1, 'linked': 0},
        },
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountBootstrapProvider.overrideWith(
            (ref) => pendingBootstrap.future,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showScoreDetailSheet(
                  context: context,
                  recordId: detail.recordId,
                  detailId: detail.id,
                  initialDetail: detail,
                ),
                child: const Text('查看评分详情'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('查看评分详情'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('未连读'), findsOneWidget);
    expect(find.text('停顿'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Hello，发音评分95.0，清晰，可与下一词连读，但未连读，词后有停顿',
      ),
      findsOneWidget,
    );
    expect(find.text('基础发音评分已生成，AI 深度总结正在准备。'), findsOneWidget);
    expect(find.text('正在加载评分详情…'), findsNothing);
  });

  testWidgets(
      'practice back skips confirmation after every question is answered',
      (tester) async {
    final firstQuestion = QuestionItem.fromJson(<String, dynamic>{
      'id': 573,
      'testId': 60,
      'part': 1,
      'seqNo': 1,
      'questionText': 'Do you like science?',
      'audioUrl': '',
      'taskType': 'question',
    });
    final secondQuestion = QuestionItem.fromJson(<String, dynamic>{
      'id': 574,
      'testId': 60,
      'part': 1,
      'seqNo': 2,
      'questionText': 'What science subject do you enjoy?',
      'audioUrl': '',
      'taskType': 'question',
    });
    const firstResult = AssessmentResult(
      recordId: 28,
      detailId: 81,
      audioPath: '',
      score: 6.5,
      transcription: 'Yes, I do.',
      words: [],
    );
    const secondResult = AssessmentResult(
      recordId: 28,
      detailId: 82,
      audioPath: '',
      score: 7,
      transcription: 'I enjoy physics.',
      words: [],
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('选题页面')),
        ),
        GoRoute(
          path: '/practice',
          builder: (context, state) => PracticePage(
            testId: 60,
            mode: 'seasonal',
            part: 1,
            initialTitle: 'Science',
            initialQuestions: SpokenQuestions(
              test: null,
              questions: [firstQuestion, secondQuestion],
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/practice');
    await tester.pumpAndSettle();

    final session = container.read(practiceSessionProvider.notifier);
    session.save(firstQuestion, firstResult);
    await tester.pump();
    await tester.tap(find.byTooltip('返回选题'));
    await tester.pumpAndSettle();
    expect(find.text('要结束本次练习吗？'), findsOneWidget);

    await tester.tap(find.text('继续练习'));
    await tester.pumpAndSettle();
    session.save(secondQuestion, secondResult);
    await tester.pump();
    await tester.tap(find.byTooltip('返回选题'));
    await tester.pumpAndSettle();

    expect(find.text('要结束本次练习吗？'), findsNothing);
    expect(find.text('选题页面'), findsOneWidget);
    expect(container.read(practiceSessionProvider).answers, isEmpty);
  });

  testWidgets(
      'history records remain interactive after non-button navigation returns',
      (tester) async {
    final firstRecord = AssessmentRecord.fromJson(<String, dynamic>{
      'id': 28,
      'testId': 60,
      'bookName': '5–8 月',
      'testName': 'Science',
      'createAt': '2026-08-13T19:41:00',
    });
    final secondRecord = AssessmentRecord.fromJson(<String, dynamic>{
      'id': 29,
      'testId': 61,
      'bookName': '剑雅 16',
      'testName': 'Test 2',
      'createAt': '2026-08-13T18:30:00',
    });
    final records = [firstRecord, secondRecord];
    final openedRecordIds = <int>[];
    final initialPage = RecordPage(
      records: records,
      hasMore: false,
      nextCursorId: null,
    );
    final router = GoRouter(
      initialLocation: '/history',
      routes: [
        GoRoute(
          path: '/history',
          builder: (context, state) => HistoryPage(initialPage: initialPage),
        ),
        GoRoute(
          path: '/history/:recordId',
          builder: (context, state) => Scaffold(
            body: Text('记录详情 ${state.pathParameters['recordId']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordDetailsLoaderProvider.overrideWithValue((recordId) async {
            openedRecordIds.add(recordId);
            return RecordDetails(
              record: records.firstWhere((record) => record.id == recordId),
              details: const [],
            );
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('5–8 月 · Science'));
    await tester.pumpAndSettle();
    expect(find.text('记录详情 28'), findsOneWidget);
    expect(
      find.byType(CircularProgressIndicator, skipOffstage: false),
      findsNothing,
    );

    // A pop is what the app bar, Android back and a completed iOS back
    // gesture ultimately perform. The existing history route must be reused.
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('剑雅 16 · Test 2'));
    await tester.pumpAndSettle();

    expect(find.text('记录详情 29'), findsOneWidget);
    expect(openedRecordIds, [28, 29]);

    // A declarative navigation return (for example browser history) must not
    // leave the source route in its pre-navigation loading state either.
    router.go('/history');
    await tester.pumpAndSettle();
    expect(
      find.byType(CircularProgressIndicator, skipOffstage: false),
      findsNothing,
    );
    await tester.tap(find.text('5–8 月 · Science'));
    await tester.pumpAndSettle();
    expect(find.text('记录详情 28'), findsOneWidget);
    expect(openedRecordIds, [28, 29, 28]);
  });

  testWidgets('prefetched routes render content without a loading page',
      (tester) async {
    final test = TestItem.fromJson(<String, dynamic>{
      'id': 60,
      'bookId': 14,
      'type': 2,
      'bookName': '5–8 月',
      'name': 'Science',
      'part': 1,
      'seqNo': 1,
      'displayName': 'Science',
    });
    final record = AssessmentRecord.fromJson(<String, dynamic>{
      'id': 28,
      'testId': 60,
      'bookName': '5–8 月',
      'testName': 'Science',
      'createAt': '2026-08-13T19:41:00',
    });
    final router = createAppRouter(onPageChanged: () {});
    addTearDown(router.dispose);

    router.go(
      '/history',
      extra: const RecordPage(
        records: [],
        hasMore: false,
        nextCursorId: null,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有练习记录'), findsOneWidget);
    expect(find.textContaining('正在加载'), findsNothing);
    expect(find.byType(ContentPlaceholder), findsNothing);

    router.push(
      '/history/${record.id}',
      extra: RecordDetails(record: record, details: const []),
    );
    await tester.pumpAndSettle();
    expect(find.text('这次练习没有明细'), findsOneWidget);
    expect(find.textContaining('正在加载'), findsNothing);
    expect(find.byType(ContentPlaceholder), findsNothing);

    router.go(
      '/practice/${test.id}?mode=seasonal&part=1',
      extra: PracticeNavigationData(
        test: test,
        questions: SpokenQuestions(
          test: test,
          questions: [
            QuestionItem.fromJson(<String, dynamic>{
              'id': 573,
              'testId': 60,
              'part': 1,
              'seqNo': 1,
              'questionText': 'Do you like science?',
              'audioUrl': '',
              'taskType': 'question',
            }),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Do you like science?'), findsOneWidget);
    expect(find.textContaining('正在加载'), findsNothing);
    expect(find.byType(ContentPlaceholder), findsNothing);
  });
}
