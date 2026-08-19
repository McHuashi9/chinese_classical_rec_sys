import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/engine/algorithm_constants.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/dialogs.dart';
import 'package:chinese_classical_rec_sys/widgets/reading_frame.dart';
import 'package:chinese_classical_rec_sys/pages/article_detail_page.dart';
import 'package:chinese_classical_rec_sys/pages/quiz_page.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/models/reading_view_data.dart';
import 'package:chinese_classical_rec_sys/widgets/empty_state.dart';
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

  // reading quiz availability 缓存（按 readingTextId 惰性检查，避免每秒 FFI）
  int? _quizCheckTextId;
  bool _hasReadingQuiz = false;
  ReadingController? _readingCtrl;

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
      if (_tabController.index == 1) {
        _refreshRecommend();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final readingCtrl = context.read<ReadingController>();
    if (!identical(readingCtrl, _readingCtrl)) {
      _readingCtrl?.removeListener(_onReadingChanged);
      _readingCtrl = readingCtrl;
      _readingCtrl!.addListener(_onReadingChanged);
    }
  }

  void _onReadingChanged() {
    if (!mounted) return;
    final readingCtrl = _readingCtrl;
    if (readingCtrl == null) return;
    if (!readingCtrl.isReading) {
      if (_quizCheckTextId != null) {
        _quizCheckTextId = null;
        _hasReadingQuiz = false;
        setState(() {});
      }
      return;
    }
    final text = readingCtrl.readingText;
    if (text != null) {
      _updateReadingQuizAvailability(text);
    }
  }

  @override
  void dispose() {
    _readingCtrl?.removeListener(_onReadingChanged);
    _readingCtrl = null;
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
          // 合法例外：TabBar 外层 Material 透明以露出页面背景。
          color: Colors.transparent,
          child: TabBar(
            controller: _tabController,
            onTap: (i) {/* _onTabChanged handles state update */},
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
                          hintStyle:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: context.appColors.inkSecondary,
                                  ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 12),
                          border: UnderlineInputBorder(
                              borderSide:
                                  BorderSide(color: context.appColors.border)),
                          enabledBorder: UnderlineInputBorder(
                              borderSide:
                                  BorderSide(color: context.appColors.border)),
                          focusedBorder: UnderlineInputBorder(
                              borderSide:
                                  BorderSide(color: context.accent, width: 2)),
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
                            color: context.appColors.ink,
                          ),
                      decoration: InputDecoration(
                        hintText: '搜索篇目或作者…',
                        hintStyle:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: context.appColors.inkSecondary,
                                ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 12),
                        border: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: context.appColors.border)),
                        enabledBorder: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: context.appColors.border)),
                        focusedBorder: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: context.accent, width: 2)),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          SizedBox(height: context.gapLg),
          Divider(color: context.appColors.border, height: 1),
          SizedBox(height: context.gapMedium),
          Expanded(
            child: filtered.isEmpty
                ? const EmptyState(title: '未找到匹配篇目')
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
                    _buildSpinBox(),
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
                  _buildSpinBox(),
                ],
              );
            },
          ),
          SizedBox(height: context.gapLg),
          Divider(color: context.appColors.border, height: 1),
          SizedBox(height: context.gapLg),
          Expanded(
            child: recs.isEmpty && _initialLoad
                ? const Center(child: CircularProgressIndicator())
                : recs.isEmpty
                    ? EmptyState(
                        title:
                            error != null ? '推荐失败，请稍后重试' : '阅读几篇文章后，这里会为你生成推荐',
                      )
                    : TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 250),
                        builder: (ctx, v, child) =>
                            Opacity(opacity: v, child: child),
                        child: ListView.builder(
                          itemCount: recs.length,
                          itemBuilder: (ctx, i) {
                            final prob =
                                (recs[i].probability * 100).toStringAsFixed(1);
                            return TextCard(
                              title: recs[i].text.title,
                              subtitle:
                                  '${recs[i].text.author} · ${recs[i].text.dynasty}',
                              trailing: Text('$prob%',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: context.accent,
                                      )),
                              onTap: () => _onSelectText(recs[i].text),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpinBox() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('篇数',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: context.appColors.inkSecondary,
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
                  color: context.appColors.ink,
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
    final grouped = groupBy(
        filtered, (ChineseText t) => t.source.isEmpty ? '未分类' : t.source);
    return ListView(
      children: [
        for (final entry in grouped.entries)
          _buildOuterGroup(entry.key, entry.value),
      ],
    );
  }

  Widget _buildOuterGroup(String source, List<ChineseText> texts) {
    final innerGrouped =
        groupBy(texts, (ChineseText t) => t.author.isEmpty ? '未分类' : t.author);
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
            children: entry.value
                .map((t) => TextCard(
                      title: t.title,
                      trailing: _ReadStatusLabel(textId: t.id),
                      onTap: () => _onSelectText(t),
                    ))
                .toList(),
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
        viewData: ReadingViewData(
      text: text,
      pages: pages,
      currentPage: currentPage,
      totalPages: totalPages,
      formattedTime: timer,
      isDark: isDark,
      elapsedSeconds: readingCtrl.elapsedSeconds,
      alreadyTracked: !readingCtrl.hasUnrecordedReading,
      annotations: readingCtrl.annotations,
      showTranslation: readingCtrl.showTranslation,
      pageStartsInTranslation: readingCtrl.pageStartsInTranslation,
      onToggleTranslation: () =>
          readingCtrl.setShowTranslation(!readingCtrl.showTranslation),
      onPaginate: (w, h) => readingCtrl.paginate(
        w.toDouble(),
        h.toDouble(),
        AppTheme.screenSizeForWidth(MediaQuery.sizeOf(context).width),
        settingsCtrl.fontScale,
        isDark,
        accentColor: context.accent,
      ),
      onNextPage: readingCtrl.nextPage,
      onPrevPage: readingCtrl.prevPage,
      onComplete: _completeReading,
      onAbandon: _confirmAbandon,
      onExit: _exitReading,
    ),
      onStartQuiz: _hasReadingQuiz ? _startQuizFromReading : null);
  }

  void _updateReadingQuizAvailability(ChineseText text) {
    if (_quizCheckTextId == text.id) return;
    _quizCheckTextId = text.id;
    final userCtrl = context.read<UserController>();
    final summary = userCtrl.getAttemptSummary(text.id);
    final hasQuiz =
        summary != null && summary.total > 0 && summary.answered < summary.total;
    if (hasQuiz != _hasReadingQuiz) {
      setState(() => _hasReadingQuiz = hasQuiz);
    } else {
      _hasReadingQuiz = hasQuiz;
    }
  }

  void _completeReading() {
    final readingCtrl = context.read<ReadingController>();
    final textId = readingCtrl.readingText?.id;
    final textTitle = readingCtrl.readingText?.title ?? '';
    _offerQuizAfterReading(textId, textTitle);
  }

  /// 阅读完成 → 测验入口三态：无题静默 / 有未答题询问开始 / 已答完提示并邀复习。
  /// 用户选择“开始做题”时保留活动阅读会话，提交答题时统一结算阅读效应；
  /// 选择“复习错题 / 稍后 / 无题”时按原逻辑结算并退出阅读。
  void _offerQuizAfterReading(int? textId, String textTitle) async {
    if (textId == null || !mounted) return;
    final coord = context.read<AppCoordinator>();
    final userCtrl = context.read<UserController>();
    final readingCtrl = context.read<ReadingController>();
    final batch = userCtrl.getQuizQuestions(textId);
    final questions = batch.questions;

    if (questions.isEmpty) {
      if (!batch.answeredAll) {
        userCtrl.disposeQuizQuestions(questions);
        coord.finishReadingSession();
        return; // 无题：不弹窗（现状）
      }
      // 已答完：先结算阅读，再视到期错题决定是否邀复习
      coord.finishReadingSession();
      final due = userCtrl.getDueReviews(textId);
      if (due.isEmpty) return;
      final review = await showConfirmDialog(
        context,
        title: '本篇练习已完成',
        content: '有 ${due.length} 道错题已到期，现在复习？',
        confirmLabel: '复习错题',
        cancelLabel: '稍后',
      );
      if (!review || !mounted) return;
      await _startReview(textId, textTitle);
      return;
    }

    // 有未答题：现弹窗 + 错题提示；同时有该篇到期错题时加第三按钮。
    // 弹窗等待不应计入阅读时间；确认开始做题后再恢复计时。
    final due = userCtrl.getDueReviews(textId);
    readingCtrl.pauseTimer();
    if (due.isNotEmpty) {
      final action = await showActionDialog(
        context,
        title: '阅读完成',
        content: '本篇共 ${questions.length} 题随堂练习，开始作答？答完立即更新你的能力画像。'
            '错题将进入复习队列。',
        actionLabels: ['开始做题', '复习错题'],
        cancelLabel: '下次再说',
      );
      if (!mounted) {
        userCtrl.disposeQuizQuestions(questions);
        coord.finishReadingSession();
        return;
      }
      if (action == null || action == -1) {
        userCtrl.disposeQuizQuestions(questions);
        coord.finishReadingSession();
        return;
      }
      if (action == 1) {
        userCtrl.disposeQuizQuestions(questions);
        coord.finishReadingSession();
        await _startReview(textId, textTitle);
        return;
      }
    } else {
      final start = await showConfirmDialog(
        context,
        title: '阅读完成',
        content: '本篇共 ${questions.length} 题随堂练习，开始作答？答完立即更新你的能力画像。'
            '错题将进入复习队列。',
        confirmLabel: '开始做题',
        cancelLabel: '下次再说',
      );
      if (!start || !mounted) {
        userCtrl.disposeQuizQuestions(questions);
        coord.finishReadingSession();
        return;
      }
    }
    // 用户选择开始做题：保留活动阅读会话；题目内存所有权随路由转移，
    // QuizPage 提交时结算阅读效应并丢弃阅读状态，然后转结果页。
    readingCtrl.resumeTimer();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => QuizPage(
          articleTitle: textTitle,
          questions: questions,
          readingController: readingCtrl,
        ),
      ),
    );
  }

  /// 阅读页底部“做题”按钮：直接进入当前篇 QuizPage，不结算/不丢弃阅读状态。
  Future<void> _startQuizFromReading() async {
    final readingCtrl = context.read<ReadingController>();
    final textId = readingCtrl.readingTextId;
    final textTitle = readingCtrl.readingText?.title ?? '';
    if (textId == null || !mounted) return;

    final userCtrl = context.read<UserController>();
    final batch = userCtrl.getQuizQuestions(textId);
    final questions = batch.questions;
    if (questions.isEmpty) {
      userCtrl.disposeQuizQuestions(questions);
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => QuizPage(
          articleTitle: textTitle,
          questions: questions,
          readingController: readingCtrl,
        ),
      ),
    );
    if (!mounted) return;
    // 若从答题页返回（未提交），阅读状态仍在；刷新“做题”按钮可用性。
    _quizCheckTextId = null;
    final text = context.read<ReadingController>().readingText;
    if (text != null) {
      _updateReadingQuizAvailability(text);
    }
    setState(() {});
  }

  /// 开始该篇错题复习：取到期错题（≤ quizBatchSize 一批）→ 复习通道答题页
  Future<void> _startReview(int textId, String textTitle) async {
    if (!mounted) return;
    final userCtrl = context.read<UserController>();
    final due = userCtrl.getDueReviews(textId);
    if (due.isEmpty) return;
    final ids = due
        .take(KnowledgeTracker.quizBatchSize)
        .map((r) => r.questionId)
        .toList();
    final questions = userCtrl.getQuestionsByIds(ids);
    if (questions.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => QuizPage(
          articleTitle: textTitle,
          questions: questions,
          isReview: true,
        ),
      ),
    );
  }

  void _confirmAbandon() async {
    final readingCtrl = context.read<ReadingController>();
    final coord = context.read<AppCoordinator>();
    if (readingCtrl.hasUnrecordedReading) {
      readingCtrl.pauseTimer();
      final text = readingCtrl.readingText;
      final minReadTime = text == null
          ? fallbackMinReadTime
          : minReadTimeSeconds(text.charCount);
      final overThreshold = readingCtrl.elapsedSeconds >= minReadTime;
      final discard = await showConfirmDialog(
        context,
        title: '放弃阅读？',
        content: overThreshold
            ? '已阅读 ${readingCtrl.formattedReadingTime}，将保存阅读记录。确定放弃？'
            : '未达到本文最低阅读时间，记录将不会保存。',
        confirmLabel: '放弃',
      );
      if (!discard) {
        readingCtrl.resumeTimer();
        return;
      }
    }
    coord.finishReadingSession();
  }

  void _exitReading() {
    final coord = context.read<AppCoordinator>();
    coord.finishReadingSession();
  }
}

class _ReadStatusLabel extends StatelessWidget {
  const _ReadStatusLabel({required this.textId});
  final int textId;

  @override
  Widget build(BuildContext context) {
    final isRead =
        context.select((ReadingController r) => r.isTextRead(textId));
    return Text(
      isRead ? '已读' : '未读',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: isRead
                ? context.appColors.success
                : context.appColors.inkSecondary,
          ),
    );
  }
}
