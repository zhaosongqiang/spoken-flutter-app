import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../core/recording/voice_recorder.dart';
import '../ui/design.dart';
import '../ui/widgets.dart';
import 'score_detail_sheet.dart';

class PracticePage extends ConsumerStatefulWidget {
  const PracticePage({
    required this.testId,
    required this.mode,
    required this.part,
    this.initialQuestions,
    this.initialTitle,
    super.key,
  });

  final int testId;
  final String mode;
  final int? part;
  final SpokenQuestions? initialQuestions;
  final String? initialTitle;

  @override
  ConsumerState<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends ConsumerState<PracticePage> {
  static const double _cardGap = 10;
  static const Duration _questionAudioDelay = Duration(milliseconds: 300);

  late Future<SpokenQuestions> _questions;
  late final VoiceRecorder _recorder;
  final ScrollController _scrollController = ScrollController();
  Timer? _questionAudioTimer;
  int? _presentedQuestionId;
  int _index = 0;
  bool _assessing = false;
  String? _assessmentError;

  @override
  void initState() {
    super.initState();
    _recorder = VoiceRecorder()..addListener(_recorderChanged);
    _questions = widget.initialQuestions == null
        ? _load()
        : Future<SpokenQuestions>.value(widget.initialQuestions!);
    _scheduleSessionBegin(widget.initialTitle ?? '口语练习');
  }

  @override
  void didUpdateWidget(covariant PracticePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.testId == widget.testId &&
        oldWidget.mode == widget.mode &&
        oldWidget.part == widget.part) {
      return;
    }
    _questionAudioTimer?.cancel();
    _presentedQuestionId = null;
    _index = 0;
    _assessmentError = null;
    _questions = widget.initialQuestions == null
        ? _load()
        : Future<SpokenQuestions>.value(widget.initialQuestions!);
    _scheduleSessionBegin(widget.initialTitle ?? '口语练习');
  }

  void _scheduleSessionBegin(String title) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = ref.read(practiceSessionProvider);
      if (session.testId == widget.testId && session.title == title) return;
      ref.read(practiceSessionProvider.notifier).begin(widget.testId, title);
    });
  }

  Future<SpokenQuestions> _load() async {
    final api = await ref.read(spokenApiProvider.future);
    return api.questions(
      widget.testId,
      part: widget.mode == 'seasonal' ? widget.part : null,
    );
  }

  void _recorderChanged() {
    if (mounted) setState(() {});
  }

  void _scheduleQuestionAudio(QuestionItem question) {
    if (_presentedQuestionId == question.id) return;
    _presentedQuestionId = question.id;
    _questionAudioTimer?.cancel();
    if (question.audioUrl.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _presentedQuestionId != question.id) return;
      _questionAudioTimer = Timer(
        _questionAudioDelay,
        () => unawaited(_autoPlayQuestionAudio(question)),
      );
    });
  }

  Future<void> _autoPlayQuestionAudio(QuestionItem question) async {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        _presentedQuestionId != question.id ||
        _recorder.status == VoiceRecorderStatus.recording ||
        _assessing) {
      return;
    }
    final audioKey = 'question-${question.id}';
    final service = ref.read(audioServiceProvider);
    if (service.activeKey == audioKey) return;
    try {
      await service.playUrl(audioKey, question.audioUrl);
    } catch (_) {
      if (mounted && _presentedQuestionId == question.id) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('题目音频自动播放失败，请点击播放按钮重试。'),
            ),
          );
      }
    }
  }

  Future<void> _toggleRecording(QuestionItem question) async {
    if (_assessing) return;
    if (_recorder.status == VoiceRecorderStatus.recording) {
      await _stopAndAssess(question);
      return;
    }
    setState(() => _assessmentError = null);
    try {
      await ref.read(audioServiceProvider).stop();
      await _recorder.start(onMaximum: () => _stopAndAssess(question));
    } catch (_) {
      // VoiceRecorder exposes a localized message through error.
    }
  }

  Future<void> _stopAndAssess(QuestionItem question) async {
    if (_assessing) return;
    try {
      final recording = await _recorder.stop();
      if (recording == null) return;
      setState(() {
        _assessing = true;
        _assessmentError = null;
      });
      final session = ref.read(practiceSessionProvider);
      final api = await ref.read(spokenApiProvider.future);
      final result = await api.assess(
        wav: recording.bytes,
        questionId: question.id,
        recordId: session.recordId,
      );
      ref.read(practiceSessionProvider.notifier).save(question, result);
    } catch (error) {
      if (mounted) setState(() => _assessmentError = error.toString());
    } finally {
      if (mounted) setState(() => _assessing = false);
    }
  }

  Future<void> _requestExit() async {
    final session = ref.read(practiceSessionProvider);
    if (session.answers.isEmpty &&
        _recorder.status == VoiceRecorderStatus.idle &&
        !_assessing) {
      goBackOr(context, '/');
      return;
    }
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('要结束本次练习吗？'),
        content: const Text('已完成的评分会保存在练习记录中。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续练习')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('结束并返回')),
        ],
      ),
    );
    if (exit == true && mounted) {
      await _leavePractice();
    }
  }

  Future<void> _leavePractice() async {
    await _recorder.cancel();
    if (!mounted) return;
    ref.read(practiceSessionProvider.notifier).clear();
    goBackOr(context, '/');
  }

  void _next(int length, {required bool answered}) {
    if (!answered) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('请先回答当前题目，完成评分后才能进入下一题。'),
          ),
        );
      return;
    }
    if (_index < length - 1) {
      setState(() {
        _index += 1;
        _assessmentError = null;
      });
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _questionAudioTimer?.cancel();
    _recorder.removeListener(_recorderChanged);
    _recorder.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialQuestions = widget.initialQuestions;
    if (initialQuestions != null) return _questionsContent(initialQuestions);
    return FutureBuilder<SpokenQuestions>(
      future: _questions,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppFrame(body: ContentPlaceholder());
        }
        if (snapshot.hasError) {
          return AppFrame(
            body: StatePanel(
              title: '题目暂时无法加载',
              description: snapshot.error.toString(),
              action: '重新加载',
              onAction: () => setState(() => _questions = _load()),
            ),
          );
        }
        return _questionsContent(snapshot.requireData);
      },
    );
  }

  Widget _questionsContent(SpokenQuestions data) {
    final questions = [...data.questions]..sort((a, b) {
        final byPart = a.part.compareTo(b.part);
        return byPart != 0 ? byPart : a.seqNo.compareTo(b.seqNo);
      });
    if (questions.isEmpty) {
      return AppFrame(
        body: StatePanel(
          title: '当前练习没有题目',
          description: '请返回题库选择其他练习。',
          action: '返回题库',
          onAction: () => goBackOr(context, '/'),
        ),
      );
    }
    if (_index >= questions.length) _index = questions.length - 1;
    return _content(data, questions);
  }

  Widget _content(SpokenQuestions data, List<QuestionItem> questions) {
    final question = questions[_index];
    _scheduleQuestionAudio(question);
    final session = ref.watch(practiceSessionProvider);
    final answeredQuestionIds =
        session.answers.map((answer) => answer.question.id).toSet();
    final allQuestionsAnswered =
        questions.every((item) => answeredQuestionIds.contains(item.id));
    final currentAnswer = session.answers
        .where((answer) => answer.question.id == question.id)
        .firstOrNull;
    final progress = (_index + 1) / questions.length;
    final atLast = _index == questions.length - 1;
    final title = data.test?.displayName.isNotEmpty == true
        ? data.test!.displayName
        : data.test?.name.isNotEmpty == true
            ? data.test!.name
            : session.title;
    if (session.title == '口语练习' && title != '口语练习') {
      _scheduleSessionBegin(title);
    }

    return AppFrame(
      padding: EdgeInsets.zero,
      bottomColor: AppColors.surface,
      bottomPadding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      bottom: _recordingDock(
        question,
        currentAnswer: currentAnswer,
        atLast: atLast,
        questionCount: questions.length,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 2),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: IconButton(
                    tooltip: '返回选题',
                    onPressed:
                        allQuestionsAnswered ? _leavePractice : _requestExit,
                    icon: const Icon(Icons.chevron_left, size: 24),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${_index + 1} / ${questions.length}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: IconButton(
                    tooltip: '结束本次练习',
                    onPressed: _requestExit,
                    icon: const Icon(Icons.close, size: 22),
                  ),
                ),
              ],
            ),
          ),
          LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: AppColors.surface,
          ),
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              children: [
                for (final answer in session.answers
                    .where((item) => item.question.id != question.id)) ...[
                  _QuestionCard(question: answer.question, compact: true),
                  const SizedBox(height: _cardGap),
                  _AnswerCard(answer: answer),
                  const SizedBox(height: _cardGap),
                ],
                _QuestionCard(question: question),
                const SizedBox(height: _cardGap),
                if (_assessing)
                  const _AssessmentState()
                else if (currentAnswer != null)
                  _AnswerCard(answer: currentAnswer),
                if (_assessmentError != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF2F0),
                      border: Border.all(color: const Color(0xFFFFCCC7)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _assessmentError!,
                      style: const TextStyle(color: Color(0xFFA8071A)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordingDock(
    QuestionItem question, {
    required CompletedAnswer? currentAnswer,
    required bool atLast,
    required int questionCount,
  }) {
    final recording = _recorder.status == VoiceRecorderStatus.recording;
    final seconds = _recorder.elapsed.inSeconds;
    return SizedBox(
      height: 82,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        recording ? '正在录音' : '时长',
                        style: TextStyle(
                          color: recording ? AppColors.accent : AppColors.muted,
                          fontSize: 11,
                          fontWeight:
                              recording ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Semantics(
                  button: true,
                  label: recording ? '停止录音' : '开始录音',
                  child: InkWell(
                    onTap: _assessing ? null : () => _toggleRecording(question),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 68,
                      height: 68,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _assessing
                            ? AppColors.surface
                            : AppColors.accentSoft,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              _assessing ? AppColors.border : AppColors.accent,
                        ),
                        child: Center(
                          child: recording
                              ? Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: AppColors.background,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                )
                              : const Icon(
                                  Icons.mic_none_rounded,
                                  color: AppColors.background,
                                  size: 28,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 72,
                  child: TextButton(
                    onPressed: recording || _assessing
                        ? null
                        : atLast
                            ? currentAnswer == null
                                ? null
                                : () => showScoreDetailSheet(
                                      context: context,
                                      recordId: currentAnswer.result.recordId,
                                      detailId: currentAnswer.result.detailId,
                                      initialDetail:
                                          _scoreDetailFor(currentAnswer),
                                    )
                            : () => _next(
                                  questionCount,
                                  answered: currentAnswer != null,
                                ),
                    child: Text(
                      atLast
                          ? currentAnswer == null
                              ? '最后一题'
                              : '查看反馈'
                          : '下一题',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_recorder.error != null)
            Text(
              _recorder.error!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.danger, fontSize: 10),
            ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question, this.compact = false});

  final QuestionItem question;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 36),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -5,
              top: 22,
              child: Transform.rotate(
                angle: 0.785398,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                  ),
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 18,
                  12,
                  10,
                  12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        question.questionText,
                        style: const TextStyle(
                          color: AppColors.foreground,
                          fontSize: 17,
                          height: 1.55,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AudioAction(
                      audioKey: 'question-${question.id}',
                      url: question.audioUrl,
                      label: '播放题目',
                      iconOnly: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer});

  final CompletedAnswer answer;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 36),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -5,
              top: 22,
              child: Transform.rotate(
                angle: 0.785398,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    border: Border.all(color: AppColors.border),
                  ),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                    child: Text(
                      answer.result.transcription,
                      style: const TextStyle(fontSize: 17, height: 1.55),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
                    decoration: const BoxDecoration(
                      color: AppColors.background,
                      border: Border(
                        top: BorderSide(color: AppColors.border),
                      ),
                      borderRadius:
                          BorderRadius.vertical(bottom: Radius.circular(8)),
                    ),
                    child: Row(
                      children: [
                        ScoreBadge(answer.result.score, maxScore: 100),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => showScoreDetailSheet(
                            context: context,
                            recordId: answer.result.recordId,
                            detailId: answer.result.detailId,
                            initialDetail: _scoreDetailFor(answer),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.muted,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                          child: const Text('查看评分详情'),
                        ),
                        const Spacer(),
                        AudioAction(
                          audioKey: 'answer-${answer.result.detailId}',
                          url: answer.result.audioPath,
                          label: '播放我的回答',
                          iconOnly: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

AssessmentDetail _scoreDetailFor(CompletedAnswer answer) => AssessmentDetail(
      id: answer.result.detailId,
      recordId: answer.result.recordId,
      questionId: answer.question.id,
      part: answer.question.part,
      seqNo: answer.question.seqNo,
      questionPrompt: answer.question.questionText,
      questionAudioUrl: answer.question.audioUrl,
      audioPath: answer.result.audioPath,
      transcription: answer.result.transcription,
      suggestedScore: answer.result.score,
      pronAccuracy: null,
      pronFluency: null,
      pronunciationWords: null,
    );

class _AssessmentState extends StatelessWidget {
  const _AssessmentState();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFE6F4FF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Expanded(child: Text('正在上传录音并生成基础评分，请不要离开页面。')),
          ],
        ),
      );
}
