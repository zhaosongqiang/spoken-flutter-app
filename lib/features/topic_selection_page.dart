import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import '../core/navigation_data.dart';
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
  TestItem? _seasonalSelected;
  TestItem? _cambridgeSelected;
  bool _loadingMore = false;
  bool _openingPage = false;
  String _search = '';
  int _part = 0;
  int _bookMin = 9;
  int _bookMax = 99;
  int _visible = pageSize;

  @override
  void initState() {
    super.initState();
    _libraries = _initialize();
  }

  TestItem? get _selected =>
      _mode == LibraryMode.seasonal ? _seasonalSelected : _cambridgeSelected;

  Future<_Libraries> _initialize() async {
    await _restorePreferences();
    return _load();
  }

  Future<_Libraries> _load() async {
    final api = await ref.read(spokenApiProvider.future);
    final seasonal = api.currentSeasonTests();
    final cambridge = api.cambridgeTests();
    final result = _Libraries(await seasonal, await cambridge);
    if (mounted && (_seasonalSelected == null || _cambridgeSelected == null)) {
      setState(() {
        if (_seasonalSelected == null && result.seasonal.tests.isNotEmpty) {
          _seasonalSelected = result.seasonal.tests.first;
        }
        if (_cambridgeSelected == null && result.cambridge.tests.isNotEmpty) {
          _cambridgeSelected = _defaultCambridgeTest(result.cambridge.tests);
        }
      });
    }
    return result;
  }

  Future<void> _restorePreferences() async {
    final preferences = await SharedPreferences.getInstance();
    final storedMode = preferences.getString('spokenLibraryMode');
    final rawSeasonal = preferences.getString('spokenSelectedSeasonal');
    final rawCambridge = preferences.getString('spokenSelectedCambridge');
    final legacySelection = preferences.getString('spokenSelectedTest');
    if (!mounted) return;
    setState(() {
      _mode = storedMode == 'cambridge'
          ? LibraryMode.cambridge
          : LibraryMode.seasonal;
      _seasonalSelected = _decodeSelection(rawSeasonal);
      _cambridgeSelected = _decodeSelection(rawCambridge);
      final legacy = _decodeSelection(legacySelection);
      if (legacy?.part == null) {
        _cambridgeSelected ??= legacy;
      } else {
        _seasonalSelected ??= legacy;
      }
    });
  }

  Future<void> _choose(TestItem test) async {
    setState(() {
      if (_mode == LibraryMode.seasonal) {
        _seasonalSelected = test;
      } else {
        _cambridgeSelected = test;
      }
    });
    final preferences = await SharedPreferences.getInstance();
    final encoded = jsonEncode(test.toJson());
    await Future.wait([
      preferences.setString('spokenSelectedTest', encoded),
      preferences.setString(
        _mode == LibraryMode.seasonal
            ? 'spokenSelectedSeasonal'
            : 'spokenSelectedCambridge',
        encoded,
      ),
    ]);
  }

  Future<void> _activate(TestItem test) async {
    if (_openingPage) return;
    if (_selected?.id == test.id) {
      await _start();
      return;
    }
    await _choose(test);
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

  Future<void> _start() async {
    final selection = _selected;
    if (selection == null || _openingPage) return;
    final mode = _mode.name;
    final part = selection.part ?? 0;
    setState(() => _openingPage = true);
    try {
      final api = await ref.read(spokenApiProvider.future);
      final questions = await api.questions(
        selection.id,
        part: mode == LibraryMode.seasonal.name ? selection.part : null,
      );
      if (!mounted) return;
      await context.push<void>(
        '/practice/${selection.id}?mode=$mode&part=$part',
        extra: PracticeNavigationData(
          test: selection,
          questions: questions,
        ),
      );
    } catch (error) {
      if (mounted) _showNavigationError('练习题目暂时无法打开', error);
    } finally {
      if (mounted) setState(() => _openingPage = false);
    }
  }

  Future<void> _openHistory() async {
    if (_openingPage) return;
    setState(() => _openingPage = true);
    try {
      await ref.read(accountBootstrapProvider.future);
      final api = await ref.read(spokenApiProvider.future);
      final page = await api.records();
      if (!mounted) return;
      await context.push<void>('/history', extra: page);
    } catch (error) {
      if (mounted) _showNavigationError('练习记录暂时无法打开', error);
    } finally {
      if (mounted) setState(() => _openingPage = false);
    }
  }

  void _showNavigationError(String message, Object error) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$message：$error')));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppFrame(
        body: FutureBuilder<_Libraries>(
          future: _libraries,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const ContentPlaceholder();
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
    final seasonalResults = libraries.seasonal.tests.where((test) {
      final matchesSearch = query.isEmpty ||
          '${test.name} ${test.displayName}'.toLowerCase().contains(query);
      return matchesSearch && (_part == 0 || test.part == _part);
    }).toList();
    final visibleSeasonal = seasonalResults.take(_visible).toList();
    final normalizedQuery = query.replaceAll(RegExp(r'\s'), '');
    final cambridgeBooks = libraries.cambridge.books.where((book) {
      final bookNumber = _bookNumber(book.bookName);
      final matchesSearch = normalizedQuery.isEmpty ||
          '${book.bookName}cambridge$bookNumber'
              .toLowerCase()
              .replaceAll(RegExp(r'\s'), '')
              .contains(normalizedQuery);
      return matchesSearch && bookNumber >= _bookMin && bookNumber <= _bookMax;
    }).toList();
    final hasResults = _mode == LibraryMode.seasonal
        ? seasonalResults.isNotEmpty
        : cambridgeBooks.isNotEmpty;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (_mode == LibraryMode.seasonal &&
            notification.metrics.axis == Axis.vertical &&
            notification.metrics.extentAfter < 80) {
          _loadMoreSeasonal(seasonalResults.length);
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
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
                    onPressed: _openHistory,
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
                  hintText:
                      _mode == LibraryMode.seasonal ? '搜索当季话题' : '搜索剑雅册数，例如 16',
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
                              : '剑雅 9–21 · 每册 4 套 Test',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _mode == LibraryMode.seasonal
                        ? '${seasonalResults.length} 题'
                        : '${cambridgeBooks.length} 册',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!hasResults)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: StatePanel(
                title: '没有匹配的练习',
                description: '换个关键词或清空筛选后再试。',
              ),
            )
          else if (_mode == LibraryMode.seasonal)
            SliverList.separated(
              itemCount: visibleSeasonal.length,
              separatorBuilder: (_, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _TestRow(
                test: visibleSeasonal[index],
                selected: _selected?.id == visibleSeasonal[index].id,
                onTap: () => _activate(visibleSeasonal[index]),
              ),
            )
          else
            SliverList.separated(
              itemCount: cambridgeBooks.length,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _CambridgeBookCard(
                key: ValueKey(cambridgeBooks[index].bookId),
                book: cambridgeBooks[index],
                selectedId: _selected?.id,
                initiallyExpanded: index < 2 ||
                    cambridgeBooks[index]
                        .tests
                        .any((test) => test.id == _selected?.id),
                onTestTap: _activate,
              ),
            ),
          if (_mode == LibraryMode.seasonal && seasonalResults.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 2),
                child: Text(
                  _visible < seasonalResults.length
                      ? '已显示 ${visibleSeasonal.length} 题，继续向下滑动自动加载'
                      : '已显示全部 ${seasonalResults.length} 题',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
      ),
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

  void _loadMoreSeasonal(int total) {
    if (_loadingMore || _visible >= total) return;
    _loadingMore = true;
    setState(() => _visible += pageSize);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadingMore = false;
    });
  }

  TestItem? _decodeSelection(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? TestItem.fromJson(Map<String, dynamic>.from(decoded))
          : null;
    } on FormatException {
      return null;
    }
  }

  TestItem _defaultCambridgeTest(List<TestItem> tests) {
    for (final test in tests) {
      if (_bookNumber(test.bookName) == 16 && test.testNo == 2) return test;
    }
    return tests.first;
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

class _CambridgeBookCard extends StatefulWidget {
  const _CambridgeBookCard({
    required this.book,
    required this.selectedId,
    required this.initiallyExpanded,
    required this.onTestTap,
    super.key,
  });

  final BookGroup book;
  final int? selectedId;
  final bool initiallyExpanded;
  final ValueChanged<TestItem> onTestTap;

  @override
  State<_CambridgeBookCard> createState() => _CambridgeBookCardState();
}

class _CambridgeBookCardState extends State<_CambridgeBookCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  int get _bookNumber =>
      int.tryParse(
        RegExp(r'\d+').firstMatch(widget.book.bookName)?.group(0) ?? '',
      ) ??
      0;

  @override
  void didUpdateWidget(covariant _CambridgeBookCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedInBook =
        widget.book.tests.any((test) => test.id == widget.selectedId);
    if (selectedInBook && oldWidget.selectedId != widget.selectedId) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                constraints: const BoxConstraints(minHeight: 60),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.foreground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_bookNumber',
                        style: const TextStyle(
                          color: AppColors.background,
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
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
                            widget.book.bookName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '完整 Part 1–3 · ${widget.book.tests.length} 套 Test',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? .5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.book.tests.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    mainAxisExtent: 52,
                  ),
                  itemBuilder: (context, index) {
                    final test = widget.book.tests[index];
                    final selected = test.id == widget.selectedId;
                    return Material(
                      color: selected
                          ? AppColors.accentSoft
                          : AppColors.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: selected ? AppColors.accent : AppColors.border,
                        ),
                      ),
                      child: InkWell(
                        onTap: () => widget.onTestTap(test),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Test ${test.testNo ?? index + 1}',
                                maxLines: 1,
                                style: TextStyle(
                                  color: selected
                                      ? AppColors.accent
                                      : AppColors.foreground,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Part 1–3',
                                maxLines: 1,
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      );
}
