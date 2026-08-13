import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../ui/design.dart';
import '../ui/widgets.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final ScrollController _controller = ScrollController();
  final List<AssessmentRecord> _records = <AssessmentRecord>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int? _cursor;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleScroll);
    _load(reset: true);
  }

  void _handleScroll() {
    if (_controller.position.extentAfter < 280 && _hasMore && !_loadingMore) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final api = await ref.read(spokenApiProvider.future);
      final page = await api.records(cursorId: reset ? null : _cursor);
      if (!mounted) return;
      setState(() {
        if (reset) _records.clear();
        _records.addAll(page.records
            .where((item) => !_records.any((record) => record.id == item.id)));
        _hasMore = page.hasMore;
        _cursor = page.nextCursorId;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppFrame(
        title: '练习记录',
        onBack: () => context.go('/'),
        body: _body(),
      );

  Widget _body() {
    if (_loading) return const StatePanel(title: '正在加载练习记录', loading: true);
    if (_error != null && _records.isEmpty) {
      return StatePanel(
        title: '记录暂时无法加载',
        description: _error,
        action: '重新加载',
        onAction: () => _load(reset: true),
      );
    }
    if (_records.isEmpty) {
      return StatePanel(
        title: '还没有练习记录',
        description: '完成一次口语练习后，评测记录会保存在这里。',
        action: '开始第一次练习',
        onAction: () => context.go('/'),
      );
    }
    final groups = <String, List<AssessmentRecord>>{};
    for (final record in _records) {
      final key = DateFormat('yyyy年M月d日').format(record.createAt);
      groups.putIfAbsent(key, () => <AssessmentRecord>[]).add(record);
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        controller: _controller,
        children: [
          const SizedBox(height: 26),
          const Eyebrow('YOUR PRACTICE'),
          const SizedBox(height: 8),
          Text('每一次开口，\n都算作进步。',
              style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 13),
          Text(
            '${_records.length} 次练习',
            style: const TextStyle(
                fontFamily: 'monospace', color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 22),
          for (final group in groups.entries) ...[
            Row(
              children: [
                Expanded(
                    child: Text(group.key,
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('${group.value.length} 条',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            for (final record in group.value) _RecordRow(record: record),
            const SizedBox(height: 24),
          ],
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (!_hasMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('已经到底了',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted)),
            ),
          if (_error != null && _records.isNotEmpty)
            TextButton(
                onPressed: () => _load(), child: Text('加载失败，点击重试：$_error')),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});

  final AssessmentRecord record;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => context.push('/history/${record.id}'),
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  record.id.toString().padLeft(2, '0').substring(
                      record.id.toString().padLeft(2, '0').length - 2),
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${record.bookName} · ${record.testName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${DateFormat('HH:mm').format(record.createAt)} · 查看完整问答与评分',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      );
}
