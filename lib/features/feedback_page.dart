import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../ui/design.dart';
import '../ui/widgets.dart';

enum FeedbackMetric { pronunciation, fluency, vocabulary, grammar }

class FeedbackPage extends ConsumerStatefulWidget {
  const FeedbackPage({
    required this.recordId,
    required this.detailId,
    required this.source,
    super.key,
  });

  final int recordId;
  final int detailId;
  final String source;

  @override
  ConsumerState<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends ConsumerState<FeedbackPage> {
  AssessmentDetail? _detail;
  AiEvaluation? _evaluation;
  FeedbackMetric _metric = FeedbackMetric.pronunciation;
  bool _loadingDetails = true;
  bool _loadingAi = false;
  bool _loadingTts = false;
  String? _detailsError;
  String? _aiError;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loadingDetails = true;
      _detailsError = null;
    });
    try {
      await ref.read(accountBootstrapProvider.future);
      final api = await ref.read(spokenApiProvider.future);
      final data = await api.recordDetails(widget.recordId);
      AssessmentDetail? detail;
      for (final candidate in data.details) {
        if (candidate.id == widget.detailId) {
          detail = candidate;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _detail = detail;
      });
      if (detail != null) unawaited(_loadAi());
    } catch (error) {
      if (mounted) setState(() => _detailsError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  Future<void> _loadAi() async {
    setState(() {
      _loadingAi = true;
      _aiError = null;
    });
    try {
      final api = await ref.read(spokenApiProvider.future);
      final evaluation = await api.aiEvaluation(widget.detailId);
      if (mounted) setState(() => _evaluation = evaluation);
    } catch (error) {
      if (mounted) setState(() => _aiError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingAi = false);
    }
  }

  Future<void> _playAi() async {
    if (_loadingTts) return;
    setState(() => _loadingTts = true);
    try {
      final api = await ref.read(spokenApiProvider.future);
      final bytes =
          await api.aiSpoken(widget.recordId, questionId: _detail?.questionId);
      await ref
          .read(audioServiceProvider)
          .playBytes('ai-${widget.detailId}', bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 标准发音生成失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingTts = false);
    }
  }

  Future<void> _copy(String value, String success) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    }
  }

  void _back() {
    if (widget.source == 'practice' && context.canPop()) {
      context.pop();
      return;
    }
    context.go('/history/${widget.recordId}');
  }

  @override
  Widget build(BuildContext context) => AppFrame(
        title: '评测反馈',
        onBack: _back,
        actions: _detail == null
            ? null
            : [
                IconButton(
                  tooltip: '复制评分摘要',
                  onPressed: () => _copy(_summaryText(), '评分摘要已复制'),
                  icon: const Icon(Icons.ios_share_outlined, size: 21),
                ),
              ],
        body: _body(),
      );

  Widget _body() {
    if (_loadingDetails) {
      return const StatePanel(title: '正在加载基础评分', loading: true);
    }
    if (_detailsError != null) {
      return StatePanel(
        title: '评测反馈加载失败',
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
        action: '返回练习记录',
        onAction: () => context.go('/history'),
      );
    }
    return ListView(
      children: [
        _ScoreSummary(detail: detail, evaluation: _evaluation),
        if (_loadingAi)
          _statusBox(
            icon: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: '正在生成深度评测反馈',
            description: '基础评分和录音已安全保存，请稍候。',
          ),
        if (_aiError != null)
          _statusBox(
            icon: const Icon(Icons.error_outline, color: AppColors.danger),
            title: 'AI 深度点评生成失败',
            description: _aiError!,
            action: TextButton(onPressed: _loadAi, child: const Text('重新生成')),
          ),
        const SizedBox(height: 10),
        _metricTabs(detail),
        const SizedBox(height: 20),
        _metricPanel(detail),
        if (_evaluation?.improvedAnswerText.isNotEmpty == true) ...[
          const SizedBox(height: 28),
          Row(
            children: [
              Text('优化后的回答', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              const Text('PART 1 规范版',
                  style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            color: AppColors.accentSoft,
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _evaluation!.improvedAnswerFeedback,
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
                      _evaluation!.improvedAnswerText,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _metricTabs(AssessmentDetail detail) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D111111),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            _metricButton(FeedbackMetric.pronunciation, '发音',
                _evaluation?.pronunciationScore ?? detail.pronunciationScore),
            _metricButton(FeedbackMetric.fluency, '流利度',
                _evaluation?.fluencyScore ?? detail.fluencyScore),
            _metricButton(FeedbackMetric.vocabulary, '词汇',
                _evaluation?.lexicalScore ?? detail.lexicalScore),
            _metricButton(FeedbackMetric.grammar, '语法',
                _evaluation?.grammarScore ?? detail.grammarScore),
          ],
        ),
      );

  Widget _metricButton(FeedbackMetric metric, String label, double? score) {
    final selected = _metric == metric;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _metric = metric),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSoft : null,
            borderRadius: BorderRadius.circular(7),
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Column(
            children: [
              Text(
                score?.toStringAsFixed(1) ?? '—',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: selected ? AppColors.foreground : AppColors.muted,
                ),
              ),
              Text(label, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricPanel(AssessmentDetail detail) {
    final ai = _evaluation;
    return switch (_metric) {
      FeedbackMetric.pronunciation => _feedbackSection(
          title: '发音反馈',
          summary: ai?.pronunciationSummary ?? '基础发音评分已生成，AI 深度总结正在准备。',
          children: [
            _pronunciationWords(
                ai?.sentencesPronunciation ?? detail.sentencesPronunciation),
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
                              'feedback-answer-${detail.id}',
                              detail.audioPath,
                            ),
                    child: const Text('我的录音'),
                  ),
                ),
              ],
            ),
          ],
        ),
      FeedbackMetric.fluency => _feedbackSection(
          title: '流利度与连贯性',
          summary: ai?.fluencySummary ?? 'AI 深度总结正在准备。',
          children: [
            _insight('表现亮点', ai?.fluencyStrengths),
            _insight('改进重点', ai?.fluencyImprovements),
          ],
        ),
      FeedbackMetric.vocabulary => _feedbackSection(
          title: '词汇反馈',
          summary: ai?.lexicalSummary ?? 'AI 深度总结正在准备。',
          children: [
            _dynamicSection('亮点表达', ai?.lexicalStrongExpressions),
            _dynamicSection('词汇改进', ai?.lexicalImprovements),
          ],
        ),
      FeedbackMetric.grammar => _feedbackSection(
          title: '语法反馈',
          summary: ai?.grammarSummary ?? 'AI 深度总结正在准备。',
          children: [
            _dynamicSection('已使用的语法结构', ai?.grammarStructures),
            _dynamicSection('语法纠错', ai?.grammarCorrections),
          ],
        ),
    };
  }

  Widget _feedbackSection({
    required String title,
    required String summary,
    required List<Widget> children,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
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
          ),
        ],
      );

  Widget _pronunciationWords(Object? source) {
    final sentences = _asList(source);
    final words = <Map<String, dynamic>>[];
    for (final sentence in sentences) {
      final details =
          sentence is Map ? _asList(sentence['details']) : const <dynamic>[];
      for (final word in details) {
        if (word is Map) words.add(Map<String, dynamic>.from(word));
      }
    }
    if (words.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 4,
      runSpacing: 6,
      children: words.map((word) {
        final score = asInt(word['pronunciation'], 100);
        final color = score >= 80
            ? const Color(0xFFDFF7E9)
            : score >= 60
                ? const Color(0xFFFFF1C9)
                : const Color(0xFFFEE4E2);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(4)),
          child: Text(asString(word['word'])),
        );
      }).toList(),
    );
  }

  Widget _insight(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text(label,
              style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(value),
        ],
      ),
    );
  }

  Widget _dynamicSection(String label, Object? value) {
    final items = _asList(value);
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text(label,
              style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (var index = 0; index < items.length; index++)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(_readableItem(items[index], index)),
            ),
        ],
      ),
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

  String _readableItem(Object? item, int index) {
    if (item is String) return item;
    if (item is Map) {
      final map = Map<String, dynamic>.from(item);
      final parts = <String>[
        asString(map['type']),
        asString(map['example']),
        asString(map['original']),
        if (map['suggestions'] is List)
          (map['suggestions'] as List).join(' / '),
        asString(map['reason']),
      ].where((value) => value.isNotEmpty).toList();
      return parts.isEmpty
          ? jsonEncode(map)
          : '${index + 1}. ${parts.join('\n')}';
    }
    return item.toString();
  }

  Widget _statusBox({
    required Widget icon,
    required String title,
    required String description,
    Widget? action,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFE6F4FF),
          border: Border.all(color: const Color(0xFFBAE0FF)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(description,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (action != null) action,
          ],
        ),
      );

  String _summaryText() {
    final detail = _detail;
    final ai = _evaluation;
    if (detail == null) return '';
    return '总分 ${(ai?.overallScore ?? detail.overallScore)?.toStringAsFixed(1) ?? '—'} / 9\n'
        '${ai?.overallSummary ?? ''}\n'
        '相关性 ${ai?.relevance ?? detail.relevance ?? '—'}% · '
        '${ai?.speed ?? detail.speed ?? '—'} 词/分钟 · '
        '${ai?.wordCount ?? detail.wordCount ?? '—'} 词';
  }
}

class _ScoreSummary extends StatelessWidget {
  const _ScoreSummary({required this.detail, required this.evaluation});

  final AssessmentDetail detail;
  final AiEvaluation? evaluation;

  @override
  Widget build(BuildContext context) {
    final score = evaluation?.overallScore ?? detail.overallScore ?? 0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.foreground,
        border: Border.all(color: AppColors.foreground),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 112,
                height: 112,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: (score / 9).clamp(0, 1),
                      strokeWidth: 12,
                      strokeCap: StrokeCap.butt,
                      color: AppColors.accent,
                      backgroundColor: const Color(0xFF555555),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            score.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontSize: 34,
                              height: 1,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('/ 9.0',
                              style: TextStyle(
                                  color: AppColors.border, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  evaluation?.overallSummary.isNotEmpty == true
                      ? evaluation!.overallSummary
                      : '基础评分已保存，正在生成深度反馈。',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.55,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.muted)),
            ),
            child: Row(
              children: [
                _stat('${evaluation?.relevance ?? detail.relevance ?? '—'}%',
                    '相关性'),
                _stat('${evaluation?.speed ?? detail.speed ?? '—'}', '词 / 分钟',
                    separated: true),
                _stat(
                    '${evaluation?.wordCount ?? detail.wordCount ?? '—'}', '词数',
                    separated: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, {bool separated = false}) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
          decoration: BoxDecoration(
            border: separated
                ? const Border(left: BorderSide(color: AppColors.muted))
                : null,
          ),
          child: Column(
            children: [
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(label,
                  style:
                      const TextStyle(color: AppColors.border, fontSize: 10)),
            ],
          ),
        ),
      );
}
