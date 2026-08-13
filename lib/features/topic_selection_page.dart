import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../ui/design.dart';
import '../ui/widgets.dart';

enum LibraryMode { seasonal, cambridge }

class _Libraries {
  const _Libraries(this.seasonal, this.cambridge);

  final SpokenLibrary seasonal;
  final SpokenLibrary cambridge;
}

class TopicSelectionPage extends ConsumerStatefulWidget {
  const TopicSelectionPage({super.key});

  @override
  ConsumerState<TopicSelectionPage> createState() => _TopicSelectionPageState();
}

class _TopicSelectionPageState extends ConsumerState<TopicSelectionPage> {
  static const pageSize = 16;
  late Future<_Libraries> _libraries;
  LibraryMode _mode = LibraryMode.seasonal;
  TestItem? _selected;
  String _search = '';
  int _part = 0;
  int _bookMin = 9;
  int _bookMax = 99;
  int _visible = pageSize;

  @override
  void initState() {
    super.initState();
    _libraries = _load();
    _restorePreferences();
  }

  Future<_Libraries> _load() async {
    final api = await ref.read(spokenApiProvider.future);
    final seasonal = api.currentSeasonTests();
    final cambridge = api.cambridgeTests();
    return _Libraries(await seasonal, await cambridge);
  }

  Future<void> _restorePreferences() async {
    final preferences = await SharedPreferences.getInstance();
    final storedMode = preferences.getString('spokenLibraryMode');
    final rawSelection = preferences.getString('spokenSelectedTest');
    if (!mounted) return;
    setState(() {
      _mode = storedMode == 'cambridge'
          ? LibraryMode.cambridge
          : LibraryMode.seasonal;
      if (rawSelection != null) {
        try {
          _selected = TestItem.fromJson(
            Map<String, dynamic>.from(jsonDecode(rawSelection) as Map),
          );
        } catch (_) {
          _selected = null;
        }
      }
    });
  }

  Future<void> _choose(TestItem test) async {
    setState(() => _selected = test);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
        'spokenSelectedTest', jsonEncode(test.toJson()));
  }

  Future<void> _changeMode(LibraryMode mode) async {
    setState(() {
      _mode = mode;
      _search = '';
      _visible = pageSize;
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('spokenLibraryMode', mode.name);
  }

  void _start() {
    final selection = _selected;
    if (selection == null) return;
    final mode = _mode.name;
    final part = selection.part ?? 0;
    context.go(
      '/practice/${selection.id}?mode=$mode&part=$part',
      extra: selection,
    );
  }

  @override
  Widget build(BuildContext context) => AppFrame(
        bottom: _selected == null
            ? null
            : Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('已选',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.muted)),
                        const SizedBox(height: 3),
                        Text(
                          _selectionTitle(_selected!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: _start, child: const Text('开始练习')),
                ],
              ),
        body: FutureBuilder<_Libraries>(
          future: _libraries,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const StatePanel(title: '正在加载口语题库', loading: true);
            }
            if (snapshot.hasError) {
              return StatePanel(
                title: '题库暂时无法加载',
                description: snapshot.error.toString(),
                action: '重新加载',
                onAction: () => setState(() => _libraries = _load()),
              );
            }
            return _content(snapshot.requireData);
          },
        ),
      );

  Widget _content(_Libraries libraries) {
    final library = _mode == LibraryMode.seasonal
        ? libraries.seasonal
        : libraries.cambridge;
    final query = _search.trim().toLowerCase();
    final filtered = library.tests.where((test) {
      final matchesSearch = query.isEmpty ||
          '${test.bookName} ${test.name} ${test.displayName}'
              .toLowerCase()
              .contains(query);
      if (_mode == LibraryMode.seasonal) {
        return matchesSearch && (_part == 0 || test.part == _part);
      }
      final bookNumber = _bookNumber(test.bookName);
      return matchesSearch && bookNumber >= _bookMin && bookNumber <= _bookMax;
    }).toList();
    final visible = filtered.take(_visible).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('IELTS SPEAKING'),
                      const SizedBox(height: 8),
                      Text('选择今天的练习',
                          style: Theme.of(context).textTheme.headlineLarge),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context.go('/history'),
                  icon: const Icon(Icons.history, size: 19),
                  label: const Text('练习记录'),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 10, bottom: 20),
            child: Text(
              '练当季高频话题，或按册完成剑雅口语真题。选择会自动保留。',
              style: TextStyle(color: AppColors.muted, height: 1.6),
            ),
          ),
        ),
        SliverToBoxAdapter(child: _modeSwitcher()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: TextField(
              onChanged: (value) => setState(() {
                _search = value;
                _visible = pageSize;
              }),
              decoration: const InputDecoration(
                hintText: '搜索话题、册数或 Test',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(child: _filters()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _mode == LibraryMode.seasonal ? '当季口语题库练习' : '刷剑雅真题',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _mode == LibraryMode.seasonal
                            ? '按话题单独练习'
                            : '剑雅 9–21 · 完整 Part 1–3',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text('${filtered.length} 项',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        if (visible.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: StatePanel(title: '没有匹配的练习', description: '换个关键词或清空筛选后再试。'),
          )
        else
          SliverList.separated(
            itemCount: visible.length,
            separatorBuilder: (_, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _TestRow(
              test: visible[index],
              selected: _selected?.id == visible[index].id,
              onTap: () => _choose(visible[index]),
            ),
          ),
        if (_visible < filtered.length)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: OutlinedButton(
                onPressed: () => setState(() => _visible += pageSize),
                child: const Text('加载更多'),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  Widget _modeSwitcher() => Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            _modeTab(LibraryMode.seasonal, '当季口语题库练习'),
            _modeTab(LibraryMode.cambridge, '刷剑雅真题'),
          ],
        ),
      );

  Widget _modeTab(LibraryMode mode, String label) {
    final selected = _mode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => _changeMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
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
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.accent : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _filters() {
    if (_mode == LibraryMode.seasonal) {
      return _horizontalChips(
          <({String label, int value})>[
            (label: '全部', value: 0),
            (label: 'Part 1', value: 1),
            (label: 'Part 2', value: 2),
            (label: 'Part 3', value: 3),
          ],
          _part,
          (value) => setState(() {
                _part = value;
                _visible = pageSize;
              }));
    }
    final selected = _bookMin * 100 + _bookMax;
    return _horizontalChips(
        <({String label, int value})>[
          (label: '全部 13 册', value: 9999),
          (label: '剑雅 17–21', value: 1721),
          (label: '剑雅 13–16', value: 1316),
          (label: '剑雅 9–12', value: 912),
        ],
        selected,
        (value) => setState(() {
              if (value == 9999) {
                _bookMin = 9;
                _bookMax = 99;
              } else {
                _bookMin = value ~/ 100;
                _bookMax = value % 100;
              }
              _visible = pageSize;
            }));
  }

  Widget _horizontalChips(
    List<({String label, int value})> values,
    int selected,
    ValueChanged<int> onSelected,
  ) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: values
              .map((item) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(item.label),
                      selected: selected == item.value,
                      onSelected: (_) => onSelected(item.value),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ))
              .toList(),
        ),
      );

  int _bookNumber(String value) =>
      int.tryParse(RegExp(r'\d+').firstMatch(value)?.group(0) ?? '') ?? 0;

  String _selectionTitle(TestItem test) {
    if (_mode == LibraryMode.seasonal) {
      return '${test.bookName} · Part ${test.part ?? '—'} · ${test.name}';
    }
    return '${test.bookName} · ${test.name}';
  }
}

class _TestRow extends StatelessWidget {
  const _TestRow({
    required this.test,
    required this.selected,
    required this.onTap,
  });

  final TestItem test;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? AppColors.accent : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    test.part == null ? 'TEST' : 'P${test.part}',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        test.name.isEmpty ? test.displayName : test.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        test.bookName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle : Icons.chevron_right,
                  color: selected ? AppColors.accent : AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      );
}
