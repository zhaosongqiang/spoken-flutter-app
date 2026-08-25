import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ielts_speaking/features/score_detail_sheet.dart';
import 'package:ielts_speaking/ui/design.dart';

void main() {
  testWidgets('feedback sheet validates and submits trimmed feedback',
      (tester) async {
    final pendingSubmit = Completer<void>();
    String? submittedContent;
    bool? result;

    await tester.pumpWidget(
      _FeedbackHarness(
        onResult: (value) => result = value,
        onSubmit: (content) {
          submittedContent = content;
          return pendingSubmit.future;
        },
      ),
    );

    await tester.tap(find.text('打开反馈'));
    await tester.pumpAndSettle();

    expect(find.text('提交反馈'), findsNWidgets(2));
    expect(find.text('0 / 500'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '提交反馈'));
    await tester.pump();
    expect(find.text('请输入反馈内容'), findsOneWidget);

    await tester.enterText(find.byType(TextField), ' 评分有误 ');
    await tester.pump();
    expect(find.text('6 / 500'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '提交反馈'));
    await tester.pump();
    expect(submittedContent, '评分有误');
    expect(find.text('正在提交…'), findsOneWidget);

    pendingSubmit.complete();
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.text('反馈任何错误或建议，帮助我们更好地优化评分服务。'), findsNothing);
  });

  testWidgets('feedback sheet keeps content available for retry after failure',
      (tester) async {
    var attempts = 0;

    await tester.pumpWidget(
      _FeedbackHarness(
        onSubmit: (content) async {
          attempts += 1;
          if (attempts == 1) throw StateError('offline');
        },
      ),
    );

    await tester.tap(find.text('打开反馈'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '评分与录音不一致');
    await tester.tap(find.widgetWithText(FilledButton, '提交反馈'));
    await tester.pump();

    expect(find.text('反馈提交失败，请检查网络后重新提交。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重新提交'), findsOneWidget);
    expect(find.text('评分与录音不一致'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '重新提交'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('提交反馈'), findsNothing);
  });
}

class _FeedbackHarness extends StatelessWidget {
  const _FeedbackHarness({
    required this.onSubmit,
    this.onResult,
  });

  final ScoreFeedbackSubmitter onSubmit;
  final ValueChanged<bool?>? onResult;

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  final result = await showScoreFeedbackSheet(
                    context: context,
                    onSubmit: onSubmit,
                  );
                  onResult?.call(result);
                },
                child: const Text('打开反馈'),
              ),
            ),
          ),
        ),
      );
}
