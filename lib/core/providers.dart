import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_service.dart';
import 'models.dart';
import 'spoken_api.dart';

final spokenApiProvider =
    FutureProvider<SpokenApi>((ref) => SpokenApi.create());

final accountBootstrapProvider = FutureProvider<AccountBootstrap>((ref) async {
  final api = await ref.watch(spokenApiProvider.future);
  return api.bootstrap();
});

final audioServiceProvider = Provider<AppAudioService>((ref) {
  final service = AppAudioService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

class CompletedAnswer {
  const CompletedAnswer({required this.question, required this.result});

  final QuestionItem question;
  final AssessmentResult result;
}

class PracticeSessionState {
  const PracticeSessionState({
    this.testId,
    this.title = '口语练习',
    this.recordId,
    this.answers = const <CompletedAnswer>[],
  });

  final int? testId;
  final String title;
  final int? recordId;
  final List<CompletedAnswer> answers;

  PracticeSessionState copyWith({
    int? testId,
    String? title,
    int? recordId,
    bool clearRecordId = false,
    List<CompletedAnswer>? answers,
  }) =>
      PracticeSessionState(
        testId: testId ?? this.testId,
        title: title ?? this.title,
        recordId: clearRecordId ? null : recordId ?? this.recordId,
        answers: answers ?? this.answers,
      );
}

class PracticeSessionController extends Notifier<PracticeSessionState> {
  @override
  PracticeSessionState build() => const PracticeSessionState();

  void begin(int testId, String title) {
    if (state.testId != testId) {
      state = PracticeSessionState(testId: testId, title: title);
    } else {
      state = state.copyWith(title: title);
    }
  }

  void save(QuestionItem question, AssessmentResult result) {
    state = state.copyWith(
      recordId: result.recordId,
      answers: <CompletedAnswer>[
        ...state.answers.where((answer) => answer.question.id != question.id),
        CompletedAnswer(question: question, result: result),
      ],
    );
  }

  void clear() => state = const PracticeSessionState();
}

final practiceSessionProvider =
    NotifierProvider<PracticeSessionController, PracticeSessionState>(
  PracticeSessionController.new,
);
