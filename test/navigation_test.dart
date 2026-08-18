import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ielts_speaking/core/models.dart';
import 'package:ielts_speaking/core/navigation_data.dart';
import 'package:ielts_speaking/core/providers.dart';
import 'package:ielts_speaking/features/feedback_page.dart';
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

  testWidgets('feedback back button pops to the existing source page',
      (tester) async {
    final pendingBootstrap = Completer<AccountBootstrap>();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('原页面')),
        ),
        GoRoute(
          path: '/feedback',
          builder: (context, state) => const FeedbackPage(
            recordId: 1,
            detailId: 2,
            source: 'history',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountBootstrapProvider.overrideWith(
            (ref) => pendingBootstrap.future,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    router.push('/feedback');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('评测反馈'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('原页面'), findsOneWidget);
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
