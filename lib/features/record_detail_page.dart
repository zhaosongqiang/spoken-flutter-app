import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../ui/design.dart';
import '../ui/widgets.dart';

class RecordDetailPage extends ConsumerStatefulWidget {
  const RecordDetailPage({
    required this.recordId,
    this.initialDetails,
    super.key,
  });

  final int recordId;
  final RecordDetails? initialDetails;

  @override
  ConsumerState<RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends ConsumerState<RecordDetailPage> {
  late Future<RecordDetails> _details;

  @override
  void initState() {
    super.initState();
    _details = widget.initialDetails == null
        ? _load()
        : Future<RecordDetails>.value(widget.initialDetails!);
  }

  Future<RecordDetails> _load() async {
    await ref.read(accountBootstrapProvider.future);
    final api = await ref.read(spokenApiProvider.future);
    return api.recordDetails(widget.recordId);
  }

  @override
  Widget build(BuildContext context) {
    final initialDetails = widget.initialDetails;
    if (initialDetails != null) return _content(initialDetails);
    return FutureBuilder<RecordDetails>(
      future: _details,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return AppFrame(
            title: '练习记录详情',
            onBack: () => goBackOr(context, '/history'),
            body: const ContentPlaceholder(),
          );
        }
        if (snapshot.hasError) {
          return AppFrame(
            title: '练习记录详情',
            onBack: () => goBackOr(context, '/history'),
            body: StatePanel(
              title: '详情暂时无法加载',
              description: snapshot.error.toString(),
              action: '重新加载',
              onAction: () => setState(() => _details = _load()),
            ),
          );
        }
        return _content(snapshot.requireData);
      },
    );
  }

  Widget _content(RecordDetails data) {
    if (data.details.isEmpty) {
      return AppFrame(
        title: '${data.record.bookName} · ${data.record.testName}',
        subtitle: '0 题 · 已完成',
        onBack: () => goBackOr(context, '/history'),
        body: StatePanel(
          title: '这次练习没有明细',
          description: '当前记录没有可展示的题目或回答。',
          action: '返回练习记录',
          onAction: () => goBackOr(context, '/history'),
        ),
      );
    }
    return AppFrame(
      title: '${data.record.bookName} · ${data.record.testName}',
      subtitle: '${data.details.length} 题 · 已完成',
      onBack: () => goBackOr(context, '/history'),
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          const LinearProgressIndicator(
            value: 1,
            minHeight: 4,
            color: AppColors.accent,
            backgroundColor: AppColors.surface,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              children: [
                for (var index = 0; index < data.details.length; index++) ...[
                  _DetailExchange(
                      index: index + 1, detail: data.details[index]),
                  if (index != data.details.length - 1)
                    const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailExchange extends StatelessWidget {
  const _DetailExchange({required this.index, required this.detail});

  final int index;
  final AssessmentDetail detail;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '第 $index 题',
        child: Column(
          children: [
            Padding(
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
                      padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              detail.questionPrompt,
                              style: const TextStyle(
                                fontSize: 17,
                                height: 1.55,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.25,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AudioAction(
                            audioKey: 'detail-question-${detail.id}',
                            url: detail.questionAudioUrl,
                            label: '播放题目',
                            iconOnly: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
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
                            detail.transcription.isEmpty
                                ? '未识别到有效回答'
                                : detail.transcription,
                            style: TextStyle(
                              color: detail.transcription.isEmpty
                                  ? AppColors.muted
                                  : AppColors.foreground,
                              fontSize: 17,
                              height: 1.55,
                              fontStyle: detail.transcription.isEmpty
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
                          decoration: const BoxDecoration(
                            color: AppColors.background,
                            border: Border(
                              top: BorderSide(color: AppColors.border),
                            ),
                            borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(8),
                            ),
                          ),
                          child: Row(
                            children: [
                              ScoreBadge(detail.overallScore),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => context.push(
                                  '/feedback/${detail.recordId}/${detail.id}?from=history',
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.muted,
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                                child: const Text('查看反馈'),
                              ),
                              const Spacer(),
                              AudioAction(
                                audioKey: 'detail-answer-${detail.id}',
                                url: detail.audioPath,
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
            ),
          ],
        ),
      );
}
