import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../ui/design.dart';
import '../ui/widgets.dart';

class RecordDetailPage extends ConsumerStatefulWidget {
  const RecordDetailPage({required this.recordId, super.key});

  final int recordId;

  @override
  ConsumerState<RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends ConsumerState<RecordDetailPage> {
  late Future<RecordDetails> _details;

  @override
  void initState() {
    super.initState();
    _details = _load();
  }

  Future<RecordDetails> _load() async {
    final api = await ref.read(spokenApiProvider.future);
    return api.recordDetails(widget.recordId);
  }

  @override
  Widget build(BuildContext context) => AppFrame(
        title: '练习记录详情',
        onBack: () => goBackOr(context, '/history'),
        body: FutureBuilder<RecordDetails>(
          future: _details,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const StatePanel(title: '正在加载记录详情', loading: true);
            }
            if (snapshot.hasError) {
              return StatePanel(
                title: '详情暂时无法加载',
                description: snapshot.error.toString(),
                action: '重新加载',
                onAction: () => setState(() => _details = _load()),
              );
            }
            return _content(snapshot.requireData);
          },
        ),
      );

  Widget _content(RecordDetails data) {
    if (data.details.isEmpty) {
      return StatePanel(
        title: '这次练习没有明细',
        description: '当前记录没有可展示的题目或回答。',
        action: '返回练习记录',
        onAction: () => context.go('/history'),
      );
    }
    return ListView(
      children: [
        const SizedBox(height: 26),
        const Eyebrow('PRACTICE RECORD'),
        const SizedBox(height: 8),
        Text(
          '${data.record.bookName}\n${data.record.testName}',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 13),
        Text(
          '${DateFormat('yyyy年M月d日 HH:mm').format(data.record.createAt)} · ${data.details.length} 题',
          style: const TextStyle(
              fontFamily: 'monospace', color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 24),
        const Divider(height: 1),
        const SizedBox(height: 28),
        for (var index = 0; index < data.details.length; index++) ...[
          _DetailExchange(index: index + 1, detail: data.details[index]),
          const SizedBox(height: 34),
        ],
      ],
    );
  }
}

class _DetailExchange extends StatelessWidget {
  const _DetailExchange({required this.index, required this.detail});

  final int index;
  final AssessmentDetail detail;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 27),
            child: Column(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PART ${detail.part} · QUESTION ${detail.seqNo}',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(detail.questionPrompt,
                            style: Theme.of(context).textTheme.titleMedium),
                        AudioAction(
                          audioKey: 'detail-question-${detail.id}',
                          url: detail.questionAudioUrl,
                          label: '播放题目',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  margin: const EdgeInsets.only(left: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(detail.transcription,
                          style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      Row(
                        children: [
                          ScoreBadge(detail.overallScore),
                          const Spacer(),
                          AudioAction(
                            audioKey: 'detail-answer-${detail.id}',
                            url: detail.audioPath,
                            label: '我的回答',
                          ),
                          TextButton(
                            onPressed: () => context.push(
                              '/feedback/${detail.recordId}/${detail.id}?from=history',
                            ),
                            child: const Text('查看反馈'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 8,
            child: RotatedBox(
              quarterTurns: 1,
              child: Text(
                index.toString().padLeft(2, '0'),
                style: const TextStyle(
                  color: AppColors.accent,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      );
}
