import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/dialogs.dart';
import 'package:chinese_classical_rec_sys/widgets/reading_frame.dart';
import 'package:chinese_classical_rec_sys/pages/article_detail_page.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/widgets/text_card.dart';

class ReadHubPage extends StatefulWidget {
  const ReadHubPage({super.key});
  @override
  State<ReadHubPage> createState() => _ReadHubPageState();
}

class _ReadHubPageState extends State<ReadHubPage>
    with TickerProviderStateMixin {

  // browsing 状态
  late final TabController _tabController;
  int _tabIndex = 0;

  // library tab 状态
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _filter = '';

  // recommend tab 状态
  int _topK = 10;
  bool _initialLoad = true;
  double _lastAverageAbility = -1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _lastAverageAbility = context.read<UserController>().averageAbility;
        if (_tabIndex == 1) _refreshRecommend();
      }
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging && mounted) {
      setState(() => _tabIndex = _tabController.index);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _filter = value.toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    final avgAbility = context.select((UserController u) => u.averageAbility);
    if (avgAbility != _lastAverageAbility) {
      _lastAverageAbility = avgAbility;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_tabIndex == 1) _refreshRecommend();
      });
    }

    final readingCtrl = context.watch<ReadingController>();
    if (readingCtrl.isReading && readingCtrl.readingText != null) {
      return _buildReadingMode();
    }
    return _buildBrowsingMode();
  }

  Widget _buildBrowsingMode() {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: TabBar(
            controller: _tabController,
            onTap: (i) { /* _onTabChanged handles state update */ },
            tabs: const [
              Tab(text: '全部'),
              Tab(text: '为你推荐'),
            ],
          ),
        ),
        Expanded(
          child: _tabIndex == 0 ? _buildLibraryTab() : _buildRecommendTab(),
        ),
      ],
    );
  }

  Widget _buildLibraryTab() {
    final allTexts = context.select((AppCoordinator c) => c.texts);
    final isDark = context.select((SettingsController s) => s.darkMode);
    final filtered = allTexts.where((t) {
      if (_filter.isEmpty) return true;
      return t.title.toLowerCase().contains(_filter) ||
          t.author.toLowerCase().contains(_filter);
    }).toList();

    return Padding(
      padding: EdgeInsets.all(context.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (ctx, constraints) {
              if (constraints.maxWidth < 480) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('文库',
                        style: Theme.of(context).textTheme.headlineLarge,
                        overflow: TextOverflow.ellipsis),
                    SizedBox(height: context.gapMedium),
                    SizedBox(
                      width: double.infinity,
                      child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        hintText: '搜索篇目或作者…',
                        hintStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        border: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.vermilion, width: 2)),
                      ),
                    ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Text(
                    '文库',
                    style: Theme.of(context).textTheme.headlineLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 260,
                    child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: isDark ? AppTheme.darkInk : AppTheme.ink,
                    ),
                    decoration: InputDecoration(
                      hintText: '搜索篇目或作者…',
                      hintStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      border: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.vermilion, width: 2)),
                    ),
                  ),
                  ),
                ],
              );
            },
          ),
          SizedBox(height: context.gapLg),
          const Divider(color: AppTheme.border, height: 1),
          SizedBox(height: context.gapMedium),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text('未找到匹配篇目',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                        )),
                  )
                : _filter.isNotEmpty
                    ? ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) => TextCard(
                          title: filtered[i].title,
                          trailing: _ReadStatusLabel(textId: filtered[i].id),
                          onTap: () => _onSelectText(filtered[i]),
                        ),
                      )
                    : _buildGroupedList(filtered),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendTab() {
    final recs = context.select((UserController u) => u.recommendations);
    final isDark = context.select((SettingsController s) => s.darkMode);
    final error = context.select((SettingsController s) => s.error);

    return Padding(
      padding: EdgeInsets.all(context.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (ctx, constraints) {
              if (constraints.maxWidth < 480) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '为你推荐',
                      style: Theme.of(context).textTheme.headlineLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: context.gapMedium),
                    _buildSpinBox(isDark),
                  ],
                );
              }
              return Row(
                children: [
                  Text(
                    '为你推荐',
                    style: Theme.of(context).textTheme.headlineLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  _buildSpinBox(isDark),
                ],
              );
            },
          ),
          SizedBox(height: context.gapLg),
          const Divider(color: AppTheme.border, height: 1),
          SizedBox(height: context.gapLg),
          Expanded(
            child: recs.isEmpty && !_initialLoad
                ? Center(
                    child: Text(
                      error != null ? '推荐失败，请稍后重试' : '能力变化时将自动生成推荐',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: recs.length,
                    itemBuilder: (ctx, i) {
                      final prob = (recs[i].probability * 100).toStringAsFixed(1);
                      return TextCard(
                        title: recs[i].text.title,
                        subtitle: '${recs[i].text.author} · ${recs[i].text.dynasty}',
                        trailing: Text('$prob%',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.vermilion,
                          )),
                        onTap: () => _onSelectText(recs[i].text),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpinBox(bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('篇数', style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
        )),
        SizedBox(width: context.gapMedium),
        IconButton(
          icon: const Icon(Icons.remove, size: 18),
          visualDensity: VisualDensity.compact,
          onPressed: _topK > 1
              ? () {
                  _topK--;
                  _refreshRecommend();
                }
              : null,
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$_topK',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: isDark ? AppTheme.darkInk : AppTheme.ink,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 18),
          visualDensity: VisualDensity.compact,
          onPressed: _topK < 50
              ? () {
                  _topK++;
                  _refreshRecommend();
                }
              : null,
        ),
      ],
    );
  }

  void _refreshRecommend() {
    context.read<AppCoordinator>().getRecommendations(_topK);
    _initialLoad = false;
  }

  Widget _buildGroupedList(List<ChineseText> filtered) {
    final grouped = groupBy(filtered, (ChineseText t) =>
        t.source.isEmpty ? '未分类' : t.source);
    return ListView(
      children: [
        for (final entry in grouped.entries)
          _buildOuterGroup(entry.key, entry.value),
      ],
    );
  }

  Widget _buildOuterGroup(String source, List<ChineseText> texts) {
    final innerGrouped = groupBy(texts, (ChineseText t) =>
        t.author.isEmpty ? '未分类' : t.author);
    return ExpansionTile(
      title: Text('$source（${texts.length}篇）'),
      initiallyExpanded: false,
      children: [
        for (final entry in innerGrouped.entries)
          ExpansionTile(
            title: Text('${entry.key}（${entry.value.length}篇）'),
            initiallyExpanded: false,
            tilePadding: const EdgeInsetsDirectional.only(start: 48),
            childrenPadding: const EdgeInsetsDirectional.only(start: 48),
            children: entry.value.map((t) => TextCard(
              title: t.title,
              trailing: _ReadStatusLabel(textId: t.id),
              onTap: () => _onSelectText(t),
            )).toList(),
          ),
      ],
    );
  }

  void _onSelectText(ChineseText text) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArticleDetailPage(textId: text.id),
      ),
    );
  }

  Widget _buildReadingMode() {
    final readingCtrl = context.watch<ReadingController>();
    final settingsCtrl = context.watch<SettingsController>();
    final text = readingCtrl.readingText;
    final isDark = settingsCtrl.darkMode;
    final pages = readingCtrl.pages;
    final currentPage = readingCtrl.currentPage;
    final totalPages = readingCtrl.totalPages;
    final timer = readingCtrl.formattedReadingTime;

    if (text == null) return _buildBrowsingMode();

    return ReadingFrame(
      text: text,
      pages: pages,
      currentPage: currentPage,
      totalPages: totalPages,
      formattedTime: timer,
      isDark: isDark,
      elapsedSeconds: readingCtrl.elapsedSeconds,
      alreadyTracked: !readingCtrl.hasUnrecordedReading,
      annotations: readingCtrl.annotations,
      onPaginate: (w, h) => readingCtrl.paginate(
        w.toDouble(), h.toDouble(),
        AppTheme.screenSizeForWidth(MediaQuery.sizeOf(context).width),
        settingsCtrl.fontScale,
      ),
      onNextPage: readingCtrl.nextPage,
      onPrevPage: readingCtrl.prevPage,
      onComplete: _completeReading,
      onAbandon: _confirmAbandon,
      onExit: _exitReading,
    );
  }

  void _completeReading() {
    final readingCtrl = context.read<ReadingController>();
    final coord = context.read<AppCoordinator>();
    coord.applyReadingEffect();
    readingCtrl.stopTimer();
    readingCtrl.discardReading();
  }

  void _confirmAbandon() async {
    final readingCtrl = context.read<ReadingController>();
    final coord = context.read<AppCoordinator>();
    if (readingCtrl.hasUnrecordedReading) {
      readingCtrl.pauseTimer();
      final over30 = readingCtrl.elapsedSeconds >= 30;
      final discard = await showConfirmDialog(context,
        title: '放弃阅读？',
        content: over30
            ? '已阅读 ${readingCtrl.formattedReadingTime}，将保存阅读记录。确定放弃？'
            : '当前阅读未满30秒，记录将不会保存。',
        confirmLabel: '放弃',
      );
      if (!discard) { readingCtrl.resumeTimer(); return; }
    }
    readingCtrl.stopTimer();
    if (readingCtrl.elapsedSeconds >= 30) {
      coord.applyReadingEffect();
    }
    readingCtrl.discardReading();
  }

  void _exitReading() {
    final readingCtrl = context.read<ReadingController>();
    final coord = context.read<AppCoordinator>();
    readingCtrl.stopTimer();
    coord.applyReadingEffect();
    readingCtrl.discardReading();
  }
}

class _ReadStatusLabel extends StatelessWidget {
  const _ReadStatusLabel({required this.textId});
  final int textId;

  @override
  Widget build(BuildContext context) {
    final isRead = context.select((ReadingController r) => r.isTextRead(textId));
    return Text(
      isRead ? '已读' : '未读',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: isRead ? AppTheme.stoneGreen : AppTheme.inkSecondary,
      ),
    );
  }
}
