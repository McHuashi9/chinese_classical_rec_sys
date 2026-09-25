import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/models/reading_view_data.dart';
import 'package:chinese_classical_rec_sys/models/text.dart';
import 'package:chinese_classical_rec_sys/pages/init_result_page.dart';
import 'package:chinese_classical_rec_sys/pages/quiz_page.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/engine/read_tracker.dart';
import 'package:chinese_classical_rec_sys/engine/algorithm_constants.dart';
import 'package:chinese_classical_rec_sys/engine/annotation_parser.dart';
import 'package:chinese_classical_rec_sys/widgets/dialogs.dart';
import 'package:chinese_classical_rec_sys/widgets/reading_frame.dart';
import 'package:chinese_classical_rec_sys/widgets/init_tutorial_overlay.dart';

/// 初始化操作引导是否已展示/跳过的 SharedPreferences 标记。
const String kInitTutorialSeenKey = 'init_tutorial_seen';

/// 初始化门禁按钮文案。
///
/// 门禁是 `allRead && allAnswered` 两条判据，文案必须说清**当前缺哪一条**：
/// 只写「请先阅读两篇文章」会在「题已答满、阅读未达标」时误导用户。
/// [unreadTitles] 为仍未达标阅读的篇名（按引导页顺序）。
/// [initQuestionCount] 为初始化题数（用户可见文案里的固定值，与题组是否已加载无关）。
String initGateButtonLabel({
  required bool allRead,
  required bool allAnswered,
  required List<String> unreadTitles,
  required int initQuestionCount,
}) {
  if (!allRead) {
    if (unreadTitles.isEmpty) return '请先阅读下面两篇文章';
    return unreadTitles.length <= 2
        ? '还需阅读：${unreadTitles.join('、')}'
        : '还需阅读 ${unreadTitles.length} 篇';
  }
  return allAnswered
      ? '提交 $initQuestionCount 题初始化'
      : '请完成 $initQuestionCount 道题';
}

/// 初始化题数（门禁文案用；`initQuestions()` 未加载时也要说得出这个数）。
const int kInitQuestionCount = 6;

/// 强制初始化引导页：按篇边读边答，两篇都答完后统一提交 6 道初始化题。
class InitOnboardingPage extends StatefulWidget {
  const InitOnboardingPage({super.key});

  @override
  State<InitOnboardingPage> createState() => _InitOnboardingPageState();
}

class _InitOnboardingPageState extends State<InitOnboardingPage> {
  List<Question>? _initQuestions;
  bool _initQuestionsLoaded = false;
  final Map<int, int?> _initAnswers = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initQuestionsLoaded) return;
    _initQuestionsLoaded = true;
    _initQuestions = context.read<UserController>().getInitQuestions();
    for (final q in _initQuestions ?? const <Question>[]) {
      _initAnswers.putIfAbsent(q.id, () => null);
    }
  }

  int get _answeredCount => _initAnswers.values.where((v) => v != null).length;

  @override
  Widget build(BuildContext context) {
    final coord = context.read<AppCoordinator>();
    final userCtrl = context.watch<UserController>();

    if (userCtrl.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('初始化完成')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle,
                    size: 64, color: context.appColors.success),
                const SizedBox(height: 16),
                const Text('已完成初始化，可以开始学习了'),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('开始使用'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final texts = coord.getInitTexts();
    final unreadTexts = [
      for (final t in texts)
        if (!coord.readTracker.isTextRead(t.id)) t
    ];
    final allRead = texts.isNotEmpty && unreadTexts.isEmpty;
    final allAnswered = _answeredCount >= (_initQuestions?.length ?? 0) &&
        (_initQuestions?.isNotEmpty ?? false);
    final questionsByText = <int, List<Question>>{};
    for (final q in _initQuestions ?? const <Question>[]) {
      questionsByText.putIfAbsent(q.textId, () => []).add(q);
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: context.appColors.paper,
        appBar: AppBar(
          // 合法例外：AppBar 透明背景以露出 Scaffold 纸色。
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const SizedBox.shrink(),
          title: const Text('初始化引导'),
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(context.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '完成 6 道题后即可正常使用',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: context.gapMedium),
              Text(
                '请先阅读下面两篇短文（可查看注释与译文），阅读时可随时进入该篇初始化题。'
                '初始化题不计入普通测验，也不会进入复习队列。',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.6),
              ),
              SizedBox(height: context.gapLg),
              Divider(color: context.appColors.border, height: 1),
              SizedBox(height: context.gapLg),
              for (var i = 0; i < texts.length; i++) ...[
                _InitArticleTile(
                  text: texts[i],
                  isRead: coord.readTracker.isTextRead(texts[i].id),
                  readSeconds: coord.readTracker.totalSecondsFor(texts[i].id),
                  minReadSeconds: minReadTimeSeconds(texts[i].charCount),
                  showTutorial: i == 0,
                  questions: questionsByText[texts[i].id] ?? const [],
                  initAnswers: _initAnswers,
                  onRead: () => _openReading(
                    texts[i],
                    questionsByText[texts[i].id] ?? const [],
                    showTutorial: i == 0,
                  ),
                  onQuiz: () => _openQuiz(
                    texts[i],
                    questionsByText[texts[i].id] ?? const [],
                  ),
                ),
                SizedBox(height: context.gapSmall),
              ],
              SizedBox(height: context.gapXl),
              Text(
                '已完成 $_answeredCount/${_initQuestions?.length ?? 0} 题 · 已保存，可稍后继续',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: context.appColors.inkSecondary,
                    ),
              ),
              SizedBox(height: context.gapMedium),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: context.accent,
                    foregroundColor: context.appColors.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: allRead && allAnswered ? _submitAllInit : null,
                  child: Text(initGateButtonLabel(
                    allRead: allRead,
                    allAnswered: allAnswered,
                    unreadTitles: [for (final t in unreadTexts) t.title],
                    initQuestionCount: kInitQuestionCount,
                  )),
                ),
              ),
              SizedBox(height: context.gapXxl),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openReading(
    ChineseText text,
    List<Question> articleQuestions, {
    required bool showTutorial,
  }) async {
    final coord = context.read<AppCoordinator>();
    // getInitTexts() 返回的是列表缓存（无正文），进入阅读前必须拉全文；
    // 否则 ReadingFrame 会显示“暂无内容”。
    final detail = coord.getTextDetail(text.id);
    if (detail == null || detail.content.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文章加载失败，请重试')),
        );
      }
      return;
    }
    final raw = coord.getAnnotations(text.id);
    final translation = coord.getTranslation(text.id);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => InitReadingPage(
          text: detail,
          annotations: AnnotationParser.parse(raw),
          translation: translation,
          showTutorial: showTutorial,
          articleQuestions: articleQuestions,
          initAnswers: _initAnswers,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openQuiz(
      ChineseText text, List<Question> articleQuestions) async {
    if (articleQuestions.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => QuizPage(
          articleTitle: text.title,
          questions: articleQuestions,
          isInitPart: true,
          initAnswers: _initAnswers,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _submitAllInit() async {
    final questions = _initQuestions;
    if (questions == null || questions.isEmpty) return;
    final qids = [for (final q in questions) q.id];
    final choices = [
      for (final q in questions)
        if (_initAnswers[q.id] != null) _initAnswers[q.id]!,
    ];
    if (choices.length != questions.length) return;

    final userCtrl = context.read<UserController>();
    final ok = userCtrl.applyInit(qids, choices);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('初始化提交失败，请重试')),
      );
      return;
    }
    // 题组内存所有权转交结果页统一释放。
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => InitResultPage(questions: questions),
      ),
    );
  }
}

class _InitArticleTile extends StatelessWidget {
  final ChineseText text;
  final bool isRead;

  /// 本篇已累计的阅读秒数（由 [ReadTracker] 提供，用于让进度可见）。
  final int readSeconds;

  /// 本篇达标所需的最低阅读秒数。
  final double minReadSeconds;

  final bool showTutorial;
  final List<Question> questions;
  final Map<int, int?> initAnswers;
  final VoidCallback onRead;
  final VoidCallback onQuiz;

  const _InitArticleTile({
    required this.text,
    required this.isRead,
    this.readSeconds = 0,
    this.minReadSeconds = 0,
    required this.showTutorial,
    required this.questions,
    required this.initAnswers,
    required this.onRead,
    required this.onQuiz,
  });

  /// 阅读进度文案：已达标显示「已读」，未达标显示还需多久，避免用户干等。
  String get _readProgressLabel {
    if (isRead) return '已读';
    final remaining = (minReadSeconds - readSeconds).ceil();
    return remaining > 0 ? '未读 · 还需 ${remaining}s' : '未读 · 可点「完成」';
  }

  @override
  Widget build(BuildContext context) {
    final answered = questions.where((q) => initAnswers[q.id] != null).length;
    final baseSubtitle = [
      if (text.author.isNotEmpty) text.author,
      if (text.dynasty.isNotEmpty) text.dynasty,
    ].join(' · ');
    final progressLine = [
      if (questions.isEmpty) null else '本篇已完成 $answered/${questions.length} 题',
      _readProgressLabel,
    ].whereType<String>().join(' · ');
    final subtitle = [
      if (baseSubtitle.isNotEmpty) baseSubtitle,
      progressLine,
    ].join('\n');
    return Card(
      child: ListTile(
        leading: Icon(
          isRead ? Icons.check_circle : Icons.menu_book,
          color: isRead ? context.appColors.success : context.accent,
        ),
        title: Text(text.title),
        subtitle: subtitle.isEmpty
            ? null
            : Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.appColors.inkSecondary,
                    ),
              ),
        isThreeLine: subtitle.isNotEmpty,
        trailing: isRead
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('已读'),
                  if (questions.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: onQuiz,
                      child: const Text('做题'),
                    ),
                  ],
                ],
              )
            : FilledButton.tonal(
                onPressed: onRead,
                child: const Text('阅读'),
              ),
      ),
    );
  }
}

/// 初始化阅读页：独立使用 [ReadingFrame]，退出时调用 [AppCoordinator.recordInitRead]。
/// 支持从阅读页进入该篇初始化题（边读边答）。
class InitReadingPage extends StatefulWidget {
  final ChineseText text;
  final Map<int, String> annotations;
  final String translation;

  /// 是否为初始化第一篇；第一篇首次进入时展示操作教程（含第 4 步“做题”）。
  final bool showTutorial;

  /// 该篇初始化题（与引导页共享同一内存块，本页不释放）。
  final List<Question> articleQuestions;

  /// 初始化答案共享表（questionId -> choice），答题时直接写入。
  final Map<int, int?> initAnswers;

  const InitReadingPage({
    super.key,
    required this.text,
    required this.annotations,
    required this.translation,
    this.showTutorial = false,
    this.articleQuestions = const [],
    this.initAnswers = const {},
  });

  @override
  State<InitReadingPage> createState() => _InitReadingPageState();
}

class _InitReadingPageState extends State<InitReadingPage> {
  late final ReadingController _readingCtrl;
  final _textKey = GlobalKey();
  final _translationButtonKey = GlobalKey();
  final _nextPageButtonKey = GlobalKey();
  final _quizButtonKey = GlobalKey();
  OverlayEntry? _tutorialOverlay;
  int _tutorialStep = 0;
  bool _recorded = false;

  @override
  void initState() {
    super.initState();
    _readingCtrl = ReadingController(ReadTracker());
    _readingCtrl.loadText(
      widget.text,
      annotations: widget.annotations,
      translation: widget.translation,
      showTranslation: context.read<SettingsController>().showTranslation,
    );
    if (widget.showTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTutorial());
    }
  }

  @override
  void dispose() {
    _hideTutorial();
    _readingCtrl.dispose();
    super.dispose();
  }

  Future<void> _maybeShowTutorial() async {
    if (!mounted || !widget.showTutorial) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (prefs.getBool(kInitTutorialSeenKey) ?? false) return;
    _showTutorial();
  }

  void _showTutorial() {
    _tutorialStep = 0;
    _tutorialOverlay?.remove();
    _tutorialOverlay = OverlayEntry(builder: (_) => _buildTutorialOverlay());
    Overlay.of(context).insert(_tutorialOverlay!);
  }

  Widget _buildTutorialOverlay() {
    return InitTutorialOverlay(
      step: _tutorialStep,
      targetRect: _targetRectForStep(_tutorialStep),
      onNext: _nextTutorialStep,
      onSkip: _skipTutorial,
      totalSteps: widget.articleQuestions.isEmpty ? 3 : 4,
    );
  }

  void _nextTutorialStep() {
    final maxStep = widget.articleQuestions.isEmpty ? 2 : 3;
    if (_tutorialStep < maxStep) {
      setState(() => _tutorialStep++);
      _tutorialOverlay?.markNeedsBuild();
    } else {
      _finishTutorial();
    }
  }

  Future<void> _skipTutorial() => _finishTutorial();

  Future<void> _finishTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kInitTutorialSeenKey, true);
    if (!mounted) return;
    _hideTutorial();
  }

  void _hideTutorial() {
    _tutorialOverlay?.remove();
    _tutorialOverlay = null;
  }

  Rect? _targetRectForStep(int step) {
    switch (step) {
      case 0:
        return _annotationTargetRect();
      case 1:
        return _rectOf(_translationButtonKey);
      case 2:
        return _rectOf(_nextPageButtonKey);
      case 3:
        return widget.articleQuestions.isEmpty ? null : _rectOf(_quizButtonKey);
    }
    return null;
  }

  Rect? _annotationTargetRect() {
    final current = _readingCtrl.pages.isNotEmpty
        ? _readingCtrl.pages[_readingCtrl.currentPage]
        : '';
    final number = _firstAnnotationOnPage(current);
    final renderObject = _textKey.currentContext?.findRenderObject();
    if (number != null && renderObject is RenderParagraph) {
      final selection = AnnotatedTextBuilder.markerSelection(current, number);
      final boxes = renderObject.getBoxesForSelection(selection);
      if (boxes.isNotEmpty) {
        final rect = boxes.first.toRect();
        return renderObject.localToGlobal(rect.topLeft) & rect.size;
      }
    }
    return _rectOf(_textKey);
  }

  int? _firstAnnotationOnPage(String page) {
    final re = RegExp(r'〔(\d+)〕');
    for (final match in re.allMatches(page)) {
      final number = int.parse(match.group(1)!);
      if (widget.annotations.containsKey(number)) return number;
    }
    return null;
  }

  Rect? _rectOf(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _startQuiz() async {
    if (widget.articleQuestions.isEmpty) return;
    final fromTutorialStep4 = _tutorialOverlay != null && _tutorialStep == 3;
    // 从教程进入答题时先结束引导，避免浮层盖在答题页上；同时视为已完成“做题”步。
    if (_tutorialOverlay != null) {
      await _finishTutorial();
      if (!mounted) return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => QuizPage(
          articleTitle: widget.text.title,
          questions: widget.articleQuestions,
          isInitPart: true,
          showQuizGuide: fromTutorialStep4,
          initAnswers: widget.initAnswers,
          readingController: _readingCtrl,
        ),
      ),
    );
  }

  /// 点「完成」：按初始化语义记录（不看阈值、不产生能力效应），并标记已读。
  void _finish() {
    if (_recorded) return;
    _recorded = true;
    final coord = context.read<AppCoordinator>();
    coord.recordInitRead(
        widget.text.id, _readingCtrl.elapsedSeconds.toDouble());
    _readingCtrl.stopTimer();
    if (mounted) Navigator.of(context).pop();
  }

  /// 点「放弃」：不记录、不标记已读，只退出本页。
  ///
  /// 与普通阅读页的放弃口径一致（未达阈值不保存）；此前这里误接 [_finish]，
  /// 导致点「放弃」也会记成已读（真机实测：读 10s 就显示「已读」）。
  Future<void> _abandon() async {
    if (_recorded) return;
    _readingCtrl.pauseTimer();
    final discard = await showConfirmDialog(
      context,
      title: '放弃阅读？',
      content: '未达到最低阅读时间，本篇不会记为已读，可稍后重新阅读。',
      confirmLabel: '放弃',
    );
    if (!mounted) return;
    if (!discard) {
      _readingCtrl.resumeTimer();
      return;
    }
    _recorded = true;
    _readingCtrl.stopTimer();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _readingCtrl,
      builder: (context, _) {
        final settingsCtrl = context.watch<SettingsController>();
        final isDark = settingsCtrl.darkMode;
        final fontScale = settingsCtrl.fontScale;
        final pages = _readingCtrl.pages;
        final currentPage = _readingCtrl.currentPage;
        final totalPages = _readingCtrl.totalPages;
        final readTracker = context.read<AppCoordinator>().readTracker;
        final initTextIds = [
          for (final t in context.read<AppCoordinator>().getInitTexts()) t.id,
        ];

        return Scaffold(
          backgroundColor: context.appColors.paper,
          body: SafeArea(
            child: ReadingFrame(
              textKey: _textKey,
              translationButtonKey: _translationButtonKey,
              nextPageButtonKey: _nextPageButtonKey,
              quizButtonKey: _quizButtonKey,
              onStartQuiz: widget.articleQuestions.isEmpty ? null : _startQuiz,
              viewData: ReadingViewData(
                text: widget.text,
                pages: pages,
                currentPage: currentPage,
                totalPages: totalPages,
                formattedTime: _readingCtrl.formattedReadingTime,
                isDark: isDark,
                elapsedSeconds: _readingCtrl.elapsedSeconds,
                alreadyTracked: false,
                // 把仍在等阅读达标的初始化篇目透传给底栏：倒计时显示「还需阅读 Ns」，
                // 否则用户只看到一个裸数字、不知道在等什么。
                pendingReadTextIds: readTracker.unreadTextIds(initTextIds),
                annotations: widget.annotations,
                showTranslation: _readingCtrl.showTranslation,
                pageStartsInTranslation: _readingCtrl.pageStartsInTranslation,
                onToggleTranslation: () => _readingCtrl
                    .setShowTranslation(!_readingCtrl.showTranslation),
                onPaginate: (w, h) => _readingCtrl.paginate(
                  w.toDouble(),
                  h.toDouble(),
                  AppTheme.screenSizeForWidth(MediaQuery.sizeOf(context).width),
                  fontScale,
                  isDark,
                  accentColor: context.accent,
                ),
                onNextPage: _readingCtrl.nextPage,
                onPrevPage: _readingCtrl.prevPage,
                onComplete: _finish,
                onAbandon: _abandon,
                onExit: _finish,
              ),
            ),
          ),
        );
      },
    );
  }
}
