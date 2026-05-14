import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
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
  AppState? _app;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _app = context.read<AppState>();
    _app!.addListener(_onAppChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tabIndex == 1) _refreshRecommend();
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
    _app?.removeListener(_onAppChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onAppChanged() {
    if (!mounted) return;
    setState(() {});
    final avg = _app!.averageAbility;
    if (avg != _lastAverageAbility) {
      _lastAverageAbility = avg;
      if (_tabIndex == 1) _refreshRecommend();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      setState(() => _filter = value.toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    if (app.isReading && app.readingText != null) {
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
    final allTexts = context.select((AppState a) => a.texts);
    final isDark = context.select((AppState a) => a.darkMode);
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
          SizedBox(height: context.gapHuge),
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
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) => TextCard(
                      title: filtered[i].title,
                      trailing: _ReadStatusLabel(textId: filtered[i].id),
                      onTap: () => _onSelectText(filtered[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendTab() {
    final recs = context.select((AppState a) => a.recommendations);
    final isDark = context.select((AppState a) => a.darkMode);

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
          SizedBox(height: context.gapHuge),
          const Divider(color: AppTheme.border, height: 1),
          SizedBox(height: context.gapHuge),
          Expanded(
            child: recs.isEmpty && !_initialLoad
                ? Center(
                    child: Text('能力变化时将自动生成推荐',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                        )),
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
    _app?.getRecommendations(_topK);
    _initialLoad = false;
  }

  void _onSelectText(ChineseText text) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArticleDetailPage(textId: text.id),
      ),
    );
  }

  Widget _buildReadingMode() {
    final app = context.read<AppState>();
    final text = app.readingText;
    final isDark = app.darkMode;
    final pages = app.pages;
    final currentPage = app.currentPage;
    final totalPages = app.totalPages;
    final timer = app.formattedReadingTime;

    if (text == null) return _buildBrowsingMode();

    return ReadingFrame(
      text: text,
      pages: pages,
      currentPage: currentPage,
      totalPages: totalPages,
      formattedTime: timer,
      isDark: isDark,
      elapsedSeconds: app.elapsedSeconds,
      alreadyTracked: !app.hasUnrecordedReading,
      onPaginate: (w, h) => app.paginate(
        w.toDouble(), h.toDouble(),
        AppTheme.screenSizeForWidth(MediaQuery.sizeOf(context).width),
      ),
      onNextPage: app.nextPage,
      onPrevPage: app.prevPage,
      onComplete: _completeReading,
      onAbandon: _confirmAbandon,
      onExit: _exitReading,
    );
  }

  void _completeReading() {
    final app = context.read<AppState>();
    app.applyReadingEffect();
    app.stopReadingTimer();
    app.discardCurrentReading();
  }

  void _confirmAbandon() async {
    final app = context.read<AppState>();
    if (app.hasUnrecordedReading) {
      app.pauseReadingTimer();
      final over30 = app.elapsedSeconds >= 30;
      final discard = await showConfirmDialog(context,
        title: '放弃阅读？',
        content: over30
            ? '已阅读 ${app.formattedReadingTime}，将保存阅读记录。确定放弃？'
            : '当前阅读未满30秒，记录将不会保存。',
        confirmLabel: '放弃',
      );
      if (!discard) { app.resumeReadingTimer(); return; }
    }
    app.stopReadingTimer();
    if (app.elapsedSeconds >= 30) {
      app.applyReadingEffect();
    }
    app.discardCurrentReading();
  }

  void _exitReading() {
    final app = context.read<AppState>();
    app.stopReadingTimer();
    app.applyReadingEffect();
    app.discardCurrentReading();
  }
}

class _ReadStatusLabel extends StatelessWidget {
  const _ReadStatusLabel({required this.textId});
  final int textId;

  @override
  Widget build(BuildContext context) {
    final isRead = context.select((AppState a) => a.isTextRead(textId));
    return Text(
      isRead ? '已读' : '未读',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: isRead ? AppTheme.stoneGreen : AppTheme.inkSecondary,
      ),
    );
  }
}
