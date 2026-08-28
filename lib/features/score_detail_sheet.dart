import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio_service.dart';
import '../core/models.dart';
import '../core/providers.dart';
import '../ui/design.dart';
import '../ui/widgets.dart';

typedef ScoreFeedbackSubmitter = Future<void> Function(String content);

Future<bool?> showScoreFeedbackSheet({
  required BuildContext context,
  required ScoreFeedbackSubmitter onSubmit,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: const Color(0x6B111111),
      backgroundColor: AppColors.background,
      constraints: const BoxConstraints(maxWidth: 480),
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) {
        final media = MediaQuery.of(context);
        final keyboardHeight = media.viewInsets.bottom;
        final availableHeight = (media.size.height - keyboardHeight)
            .clamp(0.0, media.size.height)
            .toDouble();
        final maxHeight = (availableHeight * .72).clamp(0.0, 610.0);
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: keyboardHeight),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: _ScoreFeedbackSheet(onSubmit: onSubmit),
          ),
        );
      },
    );

Future<void> showScoreDetailSheet({
  required BuildContext context,
  required int recordId,
  required int detailId,
  AssessmentDetail? initialDetail,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: const Color(0x6B111111),
      backgroundColor: AppColors.background,
      constraints: const BoxConstraints(maxWidth: 480),
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) {
        final availableHeight = MediaQuery.sizeOf(context).height;
        final desiredHeight = availableHeight * .7;
        return SizedBox(
          height: desiredHeight.clamp(0.0, availableHeight).toDouble(),
          child: ScoreDetailSheet(
            recordId: recordId,
            detailId: detailId,
            initialDetail: initialDetail,
          ),
        );
      },
    );

enum ScoreDetailTab { pronunciation, fluency, vocabulary, grammar, improved }

class ScoreDetailSheet extends ConsumerStatefulWidget {
  const ScoreDetailSheet({
    required this.recordId,
    required this.detailId,
    this.initialDetail,
    super.key,
  });

  final int recordId;
  final int detailId;
  final AssessmentDetail? initialDetail;

  @override
  ConsumerState<ScoreDetailSheet> createState() => _ScoreDetailSheetState();
}

class _ScoreDetailSheetState extends ConsumerState<ScoreDetailSheet> {
  late final AppAudioService _audioService;
  AssessmentDetail? _detail;
  AiEvaluation? _evaluation;
  ScoreDetailTab _metric = ScoreDetailTab.pronunciation;
  bool _loadingDetails = true;
  bool _loadingAi = false;
  bool _loadingTts = false;
  String? _detailsError;
  String? _aiError;
  String _aiAudioUrl = '';

  @override
  void initState() {
    super.initState();
    _audioService = ref.read(audioServiceProvider);
    _aiAudioUrl = widget.initialDetail?.aiPronunciationAudioUrl.trim() ?? '';
    unawaited(_audioService.stop());
    unawaited(_loadDetails());
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loadingDetails = widget.initialDetail == null;
      _loadingAi = false;
      _detailsError = null;
      _aiError = null;
      _detail = widget.initialDetail;
      _evaluation = null;
      _aiAudioUrl = widget.initialDetail?.aiPronunciationAudioUrl.trim() ?? '';
    });
    AssessmentDetail? detail = widget.initialDetail;
    try {
      await ref.read(accountBootstrapProvider.future);
      if (detail == null) {
        final api = await ref.read(spokenApiProvider.future);
        final data = await api.recordDetails(widget.recordId);
        for (final candidate in data.details) {
          if (candidate.id == widget.detailId) {
            detail = candidate;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loadingDetails = false;
        if (_aiAudioUrl.isEmpty) {
          _aiAudioUrl = detail?.aiPronunciationAudioUrl.trim() ?? '';
        }
      });
      if (detail != null) await _loadAi();
    } catch (error) {
      if (mounted) {
        setState(() {
          if (detail == null) {
            _detailsError = error.toString();
          } else {
            _aiError = error.toString();
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  Future<void> _loadAi() async {
    setState(() {
      _loadingAi = true;
      _aiError = null;
      _evaluation = null;
    });
    try {
      final evaluation =
          await ref.read(aiEvaluationLoaderProvider)(widget.detailId);
      if (mounted) setState(() => _evaluation = evaluation);
    } catch (error) {
      if (mounted) setState(() => _aiError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingAi = false);
    }
  }

  void _selectMetric(ScoreDetailTab metric) {
    if (_metric == metric) return;
    unawaited(_audioService.stop());
    setState(() => _metric = metric);
  }

  Future<void> _openFeedback() async {
    unawaited(_audioService.stop());
    final submitted = await showScoreFeedbackSheet(
      context: context,
      onSubmit: (content) async {
        final api = await ref.read(spokenApiProvider.future);
        await api.submitFeedback(
          detailId: widget.detailId,
          content: content,
        );
      },
    );
    if (!mounted || submitted != true) return;
    if (MediaQuery.supportsAnnounceOf(context)) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          '反馈已提交，感谢你的帮助',
          Directionality.of(context),
        ).catchError((Object _, StackTrace __) {}),
      );
    }
  }

  Future<void> _playAi() async {
    if (_loadingTts) return;
    var audioUrl = _aiAudioUrl;
    if (audioUrl.isEmpty) setState(() => _loadingTts = true);
    try {
      if (audioUrl.isEmpty) {
        final api = await ref.read(spokenApiProvider.future);
        audioUrl = await api.aiSpoken(widget.detailId);
        if (!mounted) return;
        setState(() => _aiAudioUrl = audioUrl);
      }
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      await _audioService.toggleUrl('ai-${widget.detailId}', audioUrl);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 标准发音播放失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingTts = false);
    }
  }

  @override
  void dispose() {
    unawaited(_audioService.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.background,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Text(
                      '评分详情',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: IconButton(
                          tooltip: '关闭评分详情',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _body()),
            ],
          ),
        ),
      );

  Widget _body() {
    if (_loadingDetails) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(18, 22, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text(
                  '正在加载评分详情…',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            SizedBox(height: 14),
            Expanded(child: _ScoreDetailSkeleton()),
          ],
        ),
      );
    }
    if (_detailsError != null) {
      return StatePanel(
        title: '评分详情加载失败',
        description: _detailsError,
        action: '重新加载',
        onAction: _loadDetails,
      );
    }
    final detail = _detail;
    if (detail == null) {
      return StatePanel(
        title: '还没有可查看的评测',
        description: '当前练习中没有找到这条评分明细。',
        action: '关闭',
        onAction: () => Navigator.of(context).pop(),
      );
    }
    return Column(
      children: [
        _metricTabs(),
        if (_loadingAi || _aiError != null) _aiStatus(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: _metricPanel(detail),
          ),
        ),
        _feedbackBar(),
      ],
    );
  }

  Widget _aiStatus() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        color: AppColors.surface,
        child: Row(
          children: [
            if (_loadingAi) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('AI 深度评估正在生成…')),
            ] else ...[
              const Icon(Icons.error_outline, size: 18),
              const SizedBox(width: 8),
              const Expanded(child: Text('AI 深度评估加载失败，发音词评分仍可查看。')),
              TextButton(onPressed: _loadAi, child: const Text('重试')),
            ],
          ],
        ),
      );

  Widget _feedbackBar() => Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: OutlinedButton(
          onPressed: _openFeedback,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            side: const BorderSide(color: AppColors.foreground),
            foregroundColor: AppColors.foreground,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          child: const Text('我要反馈'),
        ),
      );

  Widget _metricTabs() => DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            children: [
              _metricButton(ScoreDetailTab.pronunciation, '发音'),
              _metricButton(ScoreDetailTab.fluency, '流利度'),
              _metricButton(ScoreDetailTab.vocabulary, '词汇'),
              _metricButton(ScoreDetailTab.grammar, '语法'),
              _metricButton(ScoreDetailTab.improved, '优化后的回答'),
            ],
          ),
        ),
      );

  Widget _metricButton(ScoreDetailTab metric, String label) {
    final selected = _metric == metric;
    return Expanded(
      child: InkWell(
        onTap: () => _selectMetric(metric),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSoft : null,
            borderRadius: BorderRadius.circular(8),
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? AppColors.foreground : AppColors.muted,
              fontSize: 10,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricPanel(AssessmentDetail detail) {
    final ai = _evaluation;
    return switch (_metric) {
      ScoreDetailTab.pronunciation => _feedbackSection(
          summary: ai?.pronunciationSummary ?? '基础发音评分已生成，AI 深度总结正在准备。',
          children: [
            _pronunciationWords(detail.words),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadingTts ? null : _playAi,
                    icon: _loadingTts
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.record_voice_over, size: 18),
                    label: const Text('AI 标准发音'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: detail.audioPath.isEmpty
                        ? null
                        : () => ref.read(audioServiceProvider).toggleUrl(
                              'score-detail-answer-${detail.id}',
                              detail.audioPath,
                            ),
                    child: const Text('我的录音'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ScoreDetailTab.fluency => _feedbackSection(
          summary: ai?.fluencySummary ?? 'AI 深度总结正在准备。',
          children: [
            _insight('表现亮点', ai?.fluencyStrengths),
            _insight('改进重点', ai?.fluencyImprovements),
          ],
        ),
      ScoreDetailTab.vocabulary => _vocabularyFeedback(ai),
      ScoreDetailTab.grammar => _grammarFeedback(ai),
      ScoreDetailTab.improved => _improvedFeedback(ai),
    };
  }

  Widget _improvedFeedback(AiEvaluation? ai) {
    final feedback = ai?.improvedAnswerFeedback.trim() ?? '';
    final answer = ai?.improvedAnswerText.trim() ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            feedback.isEmpty ? '暂无优化建议。' : feedback,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              answer.isEmpty ? '暂无可优化的回答内容。' : answer,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _vocabularyFeedback(AiEvaluation? ai) {
    final strengths = _asList(ai?.lexicalStrongExpressions);
    final improvements = _asList(ai?.lexicalImprovements);
    return _feedbackSection(
      summary: ai?.lexicalSummary ?? 'AI 深度总结正在准备。',
      children: [
        if (strengths.isNotEmpty) _vocabularyStrengths(strengths),
        if (improvements.isNotEmpty)
          _correctionSection(
            '词汇改进',
            improvements,
            topMargin: strengths.isNotEmpty ? 8 : 0,
          ),
      ],
    );
  }

  Widget _grammarFeedback(AiEvaluation? ai) {
    final structures = _asList(ai?.grammarStructures);
    final corrections = _asList(ai?.grammarCorrections);
    return _feedbackSection(
      summary: ai?.grammarSummary ?? 'AI 深度总结正在准备。',
      children: [
        if (structures.isNotEmpty) _grammarStructures(structures),
        if (corrections.isNotEmpty)
          _correctionSection(
            '语法纠错',
            corrections,
            topMargin: structures.isNotEmpty ? 8 : 0,
          ),
      ],
    );
  }

  Widget _feedbackSection({
    required String summary,
    required List<Widget> children,
  }) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(summary, style: Theme.of(context).textTheme.bodyLarge),
              if (children.isNotEmpty) const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      );

  Widget _pronunciationWords(List<JsonMap> words) {
    if (words.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Wrap(
            spacing: 4,
            runSpacing: 5,
            children: words.map((word) {
              final score = asNullableDouble(word['overall']);
              final level = score == null
                  ? (
                      color: AppColors.muted,
                      label: '无评分',
                    )
                  : score >= 80
                      ? (
                          color: const Color(0xFF5BAE5F),
                          label: '清晰',
                        )
                      : score >= 60
                          ? (
                              color: const Color(0xFFDDB049),
                              label: '一般',
                            )
                          : (
                              color: const Color(0xFFEC5B57),
                              label: '需改进',
                            );
              final text = asString(word['word']);
              final scoreLabel = score?.toStringAsFixed(1) ?? '无';
              final link = asJsonMap(word['link']);
              final missedLink =
                  asInt(link['linkable']) == 1 && asInt(link['linked']) != 1;
              final pause = word['pause'] == true;
              final flowLabels = <String>[
                if (missedLink) '可与下一词连读，但未连读',
                if (pause) '词后有停顿',
              ];
              return Semantics(
                label: [
                  text,
                  '发音评分$scoreLabel',
                  level.label,
                  ...flowLabels,
                ].join('，'),
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            text,
                            style: TextStyle(
                              color: level.color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (missedLink) ...[
                          const SizedBox(width: 2),
                          Transform.translate(
                            offset: const Offset(0, -4),
                            child: const _PronunciationFlowMarker(
                              type: _PronunciationFlowType.missedLink,
                            ),
                          ),
                        ],
                        if (pause) ...[
                          const SizedBox(width: 2),
                          const _PronunciationFlowMarker(
                            type: _PronunciationFlowType.pause,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _PronunciationLegendItem(
              color: Color(0xFF5BAE5F),
              label: '清晰',
            ),
            _PronunciationLegendItem(
              color: Color(0xFFDDB049),
              label: '一般',
            ),
            _PronunciationLegendItem(
              color: Color(0xFFEC5B57),
              label: '需改进',
            ),
            _PronunciationLegendItem(
              flowType: _PronunciationFlowType.missedLink,
              label: '未连读',
            ),
            _PronunciationLegendItem(
              flowType: _PronunciationFlowType.pause,
              label: '停顿',
            ),
          ],
        ),
      ],
    );
  }

  Widget _insight(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _vocabularyStrengths(List<dynamic> items) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '亮点表达',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: items.map((item) {
                final label = item is String ? item : jsonEncode(item);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    border: Border.all(color: const Color(0x471677FF)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );

  Widget _grammarStructures(List<dynamic> items) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '已使用的语法结构',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0) const Divider(height: 29),
              _grammarStructureItem(items[index], index),
            ],
          ],
        ),
      );

  Widget _grammarStructureItem(Object? item, int index) {
    final map = item is Map
        ? Map<String, dynamic>.from(item)
        : const <String, dynamic>{};
    var type = asString(map['type']);
    final example = asString(map['example']);
    if (type.isEmpty && example.isEmpty) {
      type = item is String ? item : jsonEncode(item);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _feedbackIndex(index),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (type.isNotEmpty)
                Text(
                  type,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (example.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  example,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    height: 1.55,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _feedbackIndex(int index) => Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
        ),
        child: Text(
          '${index + 1}',
          style: const TextStyle(
            color: AppColors.background,
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _correctionSection(
    String label,
    Object? value, {
    double topMargin = 12,
  }) {
    final items = _asList(value);
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: topMargin),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const Divider(height: 29),
            _correctionItem(items[index], index),
          ],
        ],
      ),
    );
  }

  Widget _correctionItem(Object? item, int index) {
    final map = item is Map
        ? Map<String, dynamic>.from(item)
        : const <String, dynamic>{};
    final original = asString(map['original']);
    final suggestions = _asList(map['suggestions'])
        .map(asString)
        .where((value) => value.isNotEmpty)
        .toList();
    var reason = asString(map['reason']);
    if (original.isEmpty && suggestions.isEmpty && reason.isEmpty) {
      reason = item is String ? item : jsonEncode(item);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _feedbackIndex(index),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (original.isNotEmpty)
                Text(
                  original,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    height: 1.55,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              for (var suggestionIndex = 0;
                  suggestionIndex < suggestions.length;
                  suggestionIndex++) ...[
                if (original.isNotEmpty || suggestionIndex > 0)
                  const SizedBox(height: 5),
                Text(
                  '- ${suggestions[suggestionIndex]}',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (reason.isNotEmpty) ...[
                if (original.isNotEmpty || suggestions.isNotEmpty)
                  const SizedBox(height: 5),
                Text(
                  reason,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    height: 1.55,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<dynamic> _asList(Object? value) {
    if (value is List) return value;
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        return decoded is List ? decoded : <dynamic>[decoded];
      } catch (_) {
        return <dynamic>[value];
      }
    }
    return const <dynamic>[];
  }
}

class _ScoreFeedbackSheet extends StatefulWidget {
  const _ScoreFeedbackSheet({required this.onSubmit});

  final ScoreFeedbackSubmitter onSubmit;

  @override
  State<_ScoreFeedbackSheet> createState() => _ScoreFeedbackSheetState();
}

class _ScoreFeedbackSheetState extends State<_ScoreFeedbackSheet> {
  static const _maxLength = 500;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _submitting = false;
  bool _touched = false;
  bool _failedOnce = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _touched = true;
      _validate(showError: true);
    }
  }

  bool _validate({required bool showError}) {
    final valid = _controller.text.trim().isNotEmpty;
    if (mounted) {
      setState(() {
        if (!valid && showError) {
          _error = '请输入反馈内容';
        } else if (valid) {
          _error = null;
        }
      });
    }
    return valid;
  }

  void _handleChanged(String value) {
    setState(() {
      if (_touched && value.trim().isNotEmpty) _error = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    _touched = true;
    if (!_validate(showError: true)) {
      _focusNode.requestFocus();
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_controller.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _failedOnce = true;
        _error = '反馈提交失败，请检查网络后重新提交。';
      });
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Text(
                      '提交反馈',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: '关闭反馈',
                        onPressed: () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close, size: 22),
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 16),
                child: Text(
                  '反馈任何错误或建议，帮助我们更好地优化评分服务。',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    height: 1.55,
                  ),
                ),
              ),
              const Text(
                '反馈内容',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                enabled: !_submitting,
                minLines: 5,
                maxLines: 7,
                maxLength: _maxLength,
                onChanged: _handleChanged,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: '请描述你的建议或遇到的问题',
                  counterText: '',
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _error == null
                          ? AppColors.border
                          : AppColors.foreground,
                    ),
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _error ?? '',
                            style: const TextStyle(
                              color: AppColors.foreground,
                              fontSize: 12,
                              height: 1.45,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${_controller.text.length} / $_maxLength',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(
                  _submitting
                      ? '正在提交…'
                      : _failedOnce
                          ? '重新提交'
                          : '提交反馈',
                ),
              ),
            ],
          ),
        ),
      );
}

class _ScoreDetailSkeleton extends StatelessWidget {
  const _ScoreDetailSkeleton();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final blockHeight =
              ((constraints.maxHeight - 20) / 3).clamp(0.0, 58.0).toDouble();
          return Column(
            children: [
              for (var index = 0; index < 3; index++) ...[
                if (index > 0) const SizedBox(height: 10),
                Container(
                  height: blockHeight,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ],
          );
        },
      );
}

class _PronunciationLegendItem extends StatelessWidget {
  const _PronunciationLegendItem({
    required this.label,
    this.color,
    this.flowType,
  }) : assert((color == null) != (flowType == null));

  final Color? color;
  final _PronunciationFlowType? flowType;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (flowType case final flowType?)
            _PronunciationFlowMarker(type: flowType)
          else
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      );
}

enum _PronunciationFlowType { missedLink, pause }

class _PronunciationFlowMarker extends StatelessWidget {
  const _PronunciationFlowMarker({required this.type});

  final _PronunciationFlowType type;

  @override
  Widget build(BuildContext context) => switch (type) {
        _PronunciationFlowType.missedLink => const SizedBox(
            width: 15,
            height: 15,
            child: CustomPaint(
              painter: _MissedLinkPainter(color: AppColors.muted),
            ),
          ),
        _PronunciationFlowType.pause => Container(
            width: 15,
            height: 15,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.foreground),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 2,
                  height: 7,
                  decoration: BoxDecoration(
                    color: AppColors.foreground,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 2),
                Container(
                  width: 2,
                  height: 7,
                  decoration: BoxDecoration(
                    color: AppColors.foreground,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
      };
}

class _MissedLinkPainter extends CustomPainter {
  const _MissedLinkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(1.5, 10)
      ..quadraticBezierTo(size.width / 2, 4, size.width - 1.5, 10);
    for (final metric in path.computeMetrics()) {
      for (var start = 0.0; start < metric.length; start += 4) {
        final end = start + 2 < metric.length ? start + 2 : metric.length;
        canvas.drawPath(metric.extractPath(start, end), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MissedLinkPainter oldDelegate) =>
      color != oldDelegate.color;
}
