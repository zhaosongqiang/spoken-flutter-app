import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ielts_speaking/core/models.dart';
import 'package:ielts_speaking/core/providers.dart';
import 'package:ielts_speaking/core/spoken_api.dart';
import 'package:ielts_speaking/features/practice_page.dart';
import 'package:ielts_speaking/ui/design.dart';
import 'package:ielts_speaking/ui/widgets.dart';

void main() {
  testWidgets('state panel presents an actionable failure state',
      (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AppFrame(
          body: StatePanel(
            title: '题库暂时无法加载',
            description: '网络连接不可用',
            action: '重新加载',
            onAction: () => retried = true,
          ),
        ),
      ),
    );

    expect(find.text('题库暂时无法加载'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    expect(retried, isTrue);
  });

  testWidgets(
      'practice deep link initializes its session after the first frame',
      (tester) async {
    final pendingApi = Completer<SpokenApi>();
    final container = ProviderContainer(
      overrides: [
        spokenApiProvider.overrideWith((ref) => pendingApi.future),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(),
          home: const PracticePage(
            testId: 60,
            mode: 'seasonal',
            part: 1,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(container.read(practiceSessionProvider).testId, 60);
    expect(find.textContaining('正在加载'), findsNothing);
    expect(find.byType(ContentPlaceholder), findsOneWidget);
  });

  testWidgets('practice lays out short question and answer cards from the top',
      (tester) async {
    final firstQuestion = _question(1, 'What kind of science do you enjoy?');
    final secondQuestion = _question(2, 'Why is science important?');
    final container = await _pumpPractice(
      tester,
      questions: [firstQuestion, secondQuestion],
    );
    addTearDown(container.dispose);

    final conversation = find.byKey(
      const ValueKey('practice-conversation-scroll'),
    );
    final firstQuestionCard = find.byKey(
      const ValueKey('practice-question-1'),
    );
    final conversationTop = tester.getRect(conversation).top;
    final initialQuestionTop = tester.getRect(firstQuestionCard).top;
    expect(
      initialQuestionTop,
      closeTo(conversationTop + 18, 0.01),
    );
    final scrollable = find.descendant(
      of: conversation,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, 0);

    container
        .read(practiceSessionProvider.notifier)
        .save(firstQuestion, _result(1));
    await tester.pumpAndSettle();

    final firstAnswerCard = find.byKey(
      const ValueKey('practice-answer-1'),
    );
    expect(
      tester.getRect(firstQuestionCard).top,
      closeTo(initialQuestionTop, 0.01),
    );
    expect(
      tester.getRect(firstAnswerCard).top,
      closeTo(tester.getRect(firstQuestionCard).bottom + 10, 0.01),
    );
    expect(position.maxScrollExtent, 0);

    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();

    final secondQuestionCard = find.byKey(
      const ValueKey('practice-question-2'),
    );
    expect(
      tester.getRect(secondQuestionCard).top,
      closeTo(tester.getRect(firstAnswerCard).bottom + 10, 0.01),
    );
    expect(position.maxScrollExtent, 0);
    expect(firstQuestionCard, findsOneWidget);
    expect(firstAnswerCard, findsOneWidget);
  });

  testWidgets('practice starts following the latest card after overflow',
      (tester) async {
    final question = _question(1, 'What kind of science do you enjoy?');
    final container = await _pumpPractice(tester, questions: [question]);
    addTearDown(container.dispose);

    final conversation = find.byKey(
      const ValueKey('practice-conversation-scroll'),
    );
    final scrollable = find.descendant(
      of: conversation,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, 0);

    container.read(practiceSessionProvider.notifier).save(
          question,
          _result(
            1,
            transcription: List.filled(
              80,
              'This detailed answer explains why science matters.',
            ).join(' '),
          ),
        );
    await tester.pumpAndSettle();

    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.01));
    expect(
      tester.getRect(find.byKey(const ValueKey('practice-answer-1'))).bottom,
      closeTo(tester.getRect(conversation).bottom - 28, 0.01),
    );
  });

  testWidgets('practice follows new cards without resetting on other rebuilds',
      (tester) async {
    final longPrompt = List.filled(
      40,
      'Describe a scientific idea and explain why it interests you.',
    ).join(' ');
    final firstQuestion = _question(1, longPrompt);
    final secondQuestion = _question(2, 'How could people learn more?');
    final container = await _pumpPractice(
      tester,
      questions: [firstQuestion, secondQuestion],
    );
    addTearDown(container.dispose);

    final conversation = find.byKey(
      const ValueKey('practice-conversation-scroll'),
    );
    final scrollable = find.descendant(
      of: conversation,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.01));

    await tester.drag(conversation, const Offset(0, 180));
    await tester.pumpAndSettle();
    final manuallySelectedOffset = position.pixels;
    expect(manuallySelectedOffset, lessThan(position.maxScrollExtent));

    container.read(practiceSessionProvider.notifier).begin(60, 'Updated title');
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(manuallySelectedOffset, 0.01));

    container
        .read(practiceSessionProvider.notifier)
        .save(firstQuestion, _result(1));
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.01));

    await tester.drag(conversation, const Offset(0, 180));
    await tester.pumpAndSettle();
    expect(position.pixels, lessThan(position.maxScrollExtent));

    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.01));
    expect(
      tester.getRect(find.byKey(const ValueKey('practice-question-2'))).bottom,
      closeTo(tester.getRect(conversation).bottom - 28, 0.01),
    );
  });
}

QuestionItem _question(int id, String text) => QuestionItem(
      id: id,
      testId: 60,
      part: 1,
      seqNo: id,
      questionText: text,
      audioUrl: '',
      taskType: 'ANSWER_SHORT_QUESTION',
    );

AssessmentResult _result(int questionId, {String? transcription}) =>
    AssessmentResult(
      recordId: 10,
      detailId: 100 + questionId,
      audioPath: '',
      score: 7,
      transcription:
          transcription ?? 'This is my answer to question $questionId.',
      words: const [],
    );

Future<ProviderContainer> _pumpPractice(
  WidgetTester tester, {
  required List<QuestionItem> questions,
}) async {
  final container = ProviderContainer();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(),
        home: PracticePage(
          testId: 60,
          mode: 'seasonal',
          part: 1,
          initialQuestions: SpokenQuestions(test: null, questions: questions),
          initialTitle: 'Science',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}
