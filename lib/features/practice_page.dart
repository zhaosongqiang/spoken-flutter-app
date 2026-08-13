import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../core/recording/voice_recorder.dart';
import '../ui/design.dart';
import '../ui/widgets.dart';

class PracticePage extends ConsumerStatefulWidget {
  const PracticePage({
    required this.testId,
    required this.mode,
    required this.part,
    this.initialTitle,
    super.key,
  });

  final int testId;
  final String mode;
  final int? part;
  final String? initialTitle;

  @override
  ConsumerState<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends ConsumerState<PracticePage> {
  late Future<SpokenQuestions> _questions;
  late final VoiceRecorder _recorder;
  final ScrollController _scrollController = ScrollController();
  int _index = 0;
  bool _assessing = false;
  String? _assessmentError;

  @override
  void initState() {
    super.initState();
    _recorder = VoiceRecorder()..addListener(_recorderChanged);
    _questions = _load();
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
    _index = 0;
    _assessmentError = null;
    _questions = _load();
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
      context.go('/');
      return;
    }
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('要结束本次练习吗？'),
        content: const Text('已完成的评分会保存在练习记录中，未提交的录音将被丢弃。'),
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
      await _recorder.cancel();
      ref.read(practiceSessionProvider.notifier).clear();
      if (mounted) context.go('/');
    }
  }

  void _next(int length) {
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
    _recorder.removeListener(_recorderChanged);
    _recorder.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SpokenQuestions>(
        future: _questions,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AppFrame(
                body: StatePanel(title: '正在加载练习题目', loading: true));
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
          final data = snapshot.requireData;
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
                onAction: () => context.go('/'),
              ),
            );
          }
          if (_index >= questions.length) _index = questions.length - 1;
          return _content(data, questions);
        },
      );

  Widget _content(SpokenQuestions data, List<QuestionItem> questions) {
    final question = questions[_index];
    final session = ref.watch(practiceSessionProvider);
    final currentAnswer = session.answers
        .where((answer) => answer.question.id == question.id)
        .firstOrNull;
    final progress =
        (_index + (currentAnswer == null ? 0 : 1)) / questions.length;
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
      bottom: _recordingDock(question),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 54,
                  child: TextButton(
                      onPressed: _requestExit, child: const Text('返回')),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Part ${question.part} · Q${_index + 1}/${questions.length}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 54,
                  child: TextButton(
                      onPressed: _requestExit, child: const Text('结束')),
                ),
              ],
            ),
          ),
          LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: AppColors.border,
          ),
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(18, 24, 18, 28),
              children: [
                for (final answer in session.answers
                    .where((item) => item.question.id != question.id)) ...[
                  _QuestionCard(question: answer.question, compact: true),
                  const SizedBox(height: 10),
                  _AnswerCard(answer: answer),
                  const SizedBox(height: 30),
                ],
                _QuestionCard(question: question),
                const SizedBox(height: 10),
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
                if (currentAnswer != null) ...[
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: atLast
                        ? () => context.push(
                              '/feedback/${currentAnswer.result.recordId}/${currentAnswer.result.detailId}?from=practice',
                            )
                        : () => _next(questions.length),
                    child: Text(atLast ? '查看本题完整反馈' : '下一题'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordingDock(QuestionItem question) {
    final recording = _recorder.status == VoiceRecorderStatus.recording;
    final seconds = _recorder.elapsed.inSeconds;
    return SizedBox(
      height: 78,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recording
                            ? '正在录音'
                            : _assessing
                                ? '正在评测'
                                : '准备录音',
                        style: TextStyle(
                          color: recording
                              ? const Color(0xFFCF1322)
                              : AppColors.muted,
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
                Semantics(
                  button: true,
                  label: recording ? '停止录音' : '开始录音',
                  child: InkWell(
                    onTap: _assessing ? null : () => _toggleRecording(question),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: recording
                            ? const Color(0xFFFF4D4F)
                            : AppColors.background,
                        border: Border.all(
                          color: recording
                              ? const Color(0xFFFF4D4F)
                              : AppColors.foreground,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: recording ? 24 : 34,
                          height: recording ? 24 : 34,
                          decoration: BoxDecoration(
                            color:
                                recording ? Colors.white : AppColors.foreground,
                            borderRadius:
                                BorderRadius.circular(recording ? 5 : 17),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Expanded(
                  child: Text(
                    '最长 02:00',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
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
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PART ${question.part} · QUESTION ${question.seqNo}',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                question.questionText,
                style: compact
                    ? Theme.of(context).textTheme.titleMedium
                    : Theme.of(context).textTheme.titleLarge,
              ),
              if (!compact) ...[
                const SizedBox(height: 10),
                AudioAction(
                  audioKey: 'question-${question.id}',
                  url: question.audioUrl,
                  label: '播放题目',
                ),
              ],
            ],
          ),
        ),
      );
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer});

  final CompletedAnswer answer;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 22),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(answer.result.transcription,
                style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 4),
            Row(
              children: [
                ScoreBadge(answer.result.score),
                const Spacer(),
                AudioAction(
                  audioKey: 'answer-${answer.result.detailId}',
                  url: answer.result.audioPath,
                  label: '我的回答',
                ),
                TextButton(
                  onPressed: () => context.push(
                    '/feedback/${answer.result.recordId}/${answer.result.detailId}?from=practice',
                  ),
                  child: const Text('反馈'),
                ),
              ],
            ),
          ],
        ),
      );
}

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
