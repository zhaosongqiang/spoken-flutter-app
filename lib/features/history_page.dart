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
      await ref.read(accountBootstrapProvider.future);
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
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '每一次开口，\n都算作进步。',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 58),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_records.length}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 18,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text('次练习',
                        style: TextStyle(color: AppColors.muted, fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
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
            const SizedBox(height: 10),
            for (final record in group.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RecordRow(record: record),
              ),
            const SizedBox(height: 16),
          ],
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (!_hasMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('已经到底了',
                        style: TextStyle(color: AppColors.muted, fontSize: 11)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
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
  Widget build(BuildContext context) => Material(
        color: AppColors.background,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          onTap: () => context.push('/history/${record.id}'),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minHeight: 78),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.foreground,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _bookMark(record.bookName),
                    style: const TextStyle(
                      color: AppColors.background,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${record.bookName} · ${record.testName}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '口语完整练习  ·  ${DateFormat('HH:mm').format(record.createAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.muted),
              ],
            ),
          ),
        ),
      );

  String _bookMark(String value) {
    final digits = RegExp(r'\d+').firstMatch(value)?.group(0);
    if (digits != null && digits.isNotEmpty) return digits;
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'P' : trimmed.substring(0, 1).toUpperCase();
  }
}
