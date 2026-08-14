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
  final TextEditingController _searchController = TextEditingController();
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
    _searchController.clear();
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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppFrame(
        bottom: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 16, color: AppColors.muted),
                const SizedBox(width: 7),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: _selected == null ? '请先选择一项练习' : '已选  ',
                      children: _selected == null
                          ? null
                          : [
                              TextSpan(
                                text: _selectionTitle(_selected!),
                                style: const TextStyle(
                                  color: AppColors.foreground,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _selected == null ? null : _start,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(_mode == LibraryMode.seasonal ? '开始话题练习' : '开始完整练习'),
            ),
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
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('IELTS SPEAKING'),
                      const SizedBox(height: 4),
                      Text('选择今天的练习',
                          style: Theme.of(context).textTheme.headlineLarge),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/history'),
                  icon: const Icon(Icons.history, size: 19),
                  label: const Text('练习记录', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 10, bottom: 18),
            child: Text(
              '练当季高频话题，或按册完成剑雅口语真题。选择会自动保留。',
              style: TextStyle(color: AppColors.muted, height: 1.6),
            ),
          ),
        ),
        SliverToBoxAdapter(child: _modeSwitcher()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() {
                _search = value;
                _visible = pageSize;
              }),
              decoration: InputDecoration(
                hintText: '搜索话题、册数或 Test',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空搜索',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _search = '';
                            _visible = pageSize;
                          });
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
                isDense: true,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(child: _filters(library)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 10),
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
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    )),
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
            separatorBuilder: (_, index) => const SizedBox(height: 8),
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
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
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
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.background : Colors.transparent,
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
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: selected ? AppColors.accent : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _filters(SpokenLibrary library) {
    if (_mode == LibraryMode.seasonal) {
      int count(int part) => part == 0
          ? library.tests.length
          : library.tests.where((test) => test.part == part).length;
      return _horizontalChips(
          <({String label, int value})>[
            (label: '全部 ${count(0)}', value: 0),
            (label: 'Part 1 · ${count(1)}', value: 1),
            (label: 'Part 2 · ${count(2)}', value: 2),
            (label: 'Part 3 · ${count(3)}', value: 3),
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
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: ChoiceChip(
                        label: Text(item.label),
                        selected: selected == item.value,
                        showCheckmark: false,
                        onSelected: (_) => onSelected(item.value),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
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
        color: selected ? AppColors.accentSoft : AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? AppColors.accent : AppColors.border,
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.background : AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    test.part == null ? 'TEST' : 'Part ${test.part}',
                    style: TextStyle(
                      color: selected ? AppColors.accent : AppColors.muted,
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
                        test.part == null
                            ? test.bookName
                            : '${test.bookName} · 话题练习',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 20,
                    color: selected ? AppColors.accent : AppColors.muted),
              ],
            ),
          ),
        ),
      );
}
