import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/pages/quiz_result_page.dart';
import 'package:chinese_classical_rec_sys/pages/reading_preview_page.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/reading_controller.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/marked_sentence.dart';
import 'package:chinese_classical_rec_sys/widgets/init_quiz_guide_overlay.dart';

/// 文章题组答题页：一屏一题，末题提交（题组后统一判分，提交前可回改）
/// [isReview] 错题复习模式：标题区分，提交走复习通道（不产生答题效应）
/// [isInitPart] 初始化按篇模式：只记录答案并返回，不调用 user_init_apply。
/// [readingController] 从活动阅读进入时传入同一 ReadingController，供“原文”复用。
class QuizPage extends StatefulWidget {
  final String articleTitle;
  final List<Question> questions;
  final bool isReview;
  final bool isInitPart;

  /// 从阅读教程第 4 步进入时置为 true，答题页继续展示“第 5 步”回看原文引导。
  final bool showQuizGuide;

  /// 初始化按篇模式共享的答案表（questionId -> choice），选择时直接写入；
  /// 传 null 时使用页内私有状态（普通/复习答题）。
  final Map<int, int?>? initAnswers;

  /// 活动阅读会话（普通阅读为全局 ReadingController，初始化阅读为页内局部
  /// ReadingController）；null 表示独立答题，原文走只读预览。
  final ReadingController? readingController;

  const QuizPage({
    super.key,
    required this.articleTitle,
    required this.questions,
    this.isReview = false,
    this.isInitPart = false,
    this.showQuizGuide = false,
    this.initAnswers,
    this.readingController,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  /// 每题作答（定长，与 questions 等长；前进后退只移动指针，答案保留）
  late final List<int?> _choices;
  int _index = 0;

  /// 题目内存所有权：默认在本页 dispose 时释放；
  /// 提交成功转移给结果页后置位，本页不再释放（结果页销毁时统一释放）
  bool _ownershipTransferred = false;

  /// 初始化答题页“回看原文”引导浮层。
  final GlobalKey _originalButtonKey = GlobalKey();
  OverlayEntry? _quizGuideOverlay;

  UserController? _userCtrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // dispose 中不可做 ancestor lookup，提前缓存
    _userCtrl ??= context.read<UserController>();
  }

  @override
  void dispose() {
    _hideQuizGuide();
    // 初始化按篇模式使用共享答案表和共享题组内存，不由本页释放。
    if (!widget.isInitPart && !_ownershipTransferred) {
      _userCtrl?.disposeQuizQuestions(widget.questions);
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // 定长作答数组：前进后退只移动指针，回改不丢后续答案
    _choices = List<int?>.filled(widget.questions.length, null);
    if (widget.isInitPart && widget.initAnswers != null) {
      for (var i = 0; i < widget.questions.length; i++) {
        _choices[i] = widget.initAnswers![widget.questions[i].id];
      }
    }
    if (widget.isInitPart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowQuizGuide());
    }
  }

  Future<void> _maybeShowQuizGuide() async {
    if (!mounted || !widget.isInitPart) return;
    if (widget.showQuizGuide) {
      _showQuizGuide(isStep5: true);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (prefs.getBool(kInitQuizGuideSeenKey) ?? false) return;
    _showQuizGuide(isStep5: false);
  }

  void _showQuizGuide({required bool isStep5}) {
    _quizGuideOverlay?.remove();
    _quizGuideOverlay = OverlayEntry(
      builder: (_) => InitQuizGuideOverlay(
        targetRect: _rectOf(_originalButtonKey),
        isStep5: isStep5,
        onSkip: _finishQuizGuide,
      ),
    );
    Overlay.of(context).insert(_quizGuideOverlay!);
  }

  Rect? _rectOf(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _finishQuizGuide() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kInitQuizGuideSeenKey, true);
    if (!mounted) return;
    _hideQuizGuide();
  }

  void _hideQuizGuide() {
    _quizGuideOverlay?.remove();
    _quizGuideOverlay = null;
  }

  bool get _isLast => _index == widget.questions.length - 1;
  bool get _allowSubmit => _isLast && _choices.every((c) => c != null);

  int get _unansweredCount =>
      widget.questions.length - _choices.where((c) => c != null).length;

  void _selectOption(int opt) {
    setState(() => _choices[_index] = opt);
    if (widget.isInitPart && widget.initAnswers != null) {
      widget.initAnswers![widget.questions[_index].id] = opt;
    }
  }

  void _next() {
    if (_isLast) return;
    setState(() => _index++);
  }

  void _prev() {
    if (_index <= 0) return;
    setState(() => _index--);
  }

  Future<void> _submit() async {
    // 初始化按篇模式：只记录答案并返回，不调用 user_init_apply。
    if (widget.isInitPart) {
      _finishPart();
      return;
    }

    final coord = context.read<AppCoordinator>();
    // 数据库替换窗口（引擎关闭重开）内提交会静默 NOT_INIT：短路并提示重试
    if (coord.syncing.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('数据同步中，请稍后重试')),
      );
      return;
    }
    final userCtrl = context.read<UserController>();
    final choices = List.generate(widget.questions.length, (i) => _choices[i]!);

    // 从活动阅读进入的普通答题：提交时统一结算阅读效应并丢弃阅读状态。
    _settleActiveReadingIfNeeded();

    final answers = userCtrl.submitQuiz(
      widget.questions,
      choices,
      isReview: widget.isReview,
    );
    if (!mounted) return;
    if (answers == null) {
      // 首题即判题失败：无任何题生效，留在答题页可重试（不会重复计分）
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提交失败，请重试')),
      );
      return;
    }
    // 部分判题失败时 C++ 逐题落库、成功部分不回滚：结果页只展示已生效的前 N 题，
    // 不留在答题页——否则再次提交会把已生效题目重复计入能力
    final credited = answers.length;
    // 题目内存所有权转移给结果页（结果页销毁时释放），本页 dispose 不再释放
    _ownershipTransferred = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => QuizResultPage(
          articleTitle: widget.articleTitle,
          answers: answers,
          questions: credited < widget.questions.length
              ? widget.questions.sublist(0, credited)
              : widget.questions,
          totalQuestions: widget.questions.length,
          isReview: widget.isReview,
        ),
      ),
    );
  }

  void _finishPart() {
    Navigator.of(context).pop();
  }

  void _settleActiveReadingIfNeeded() {
    final controller = widget.readingController;
    if (controller == null || !controller.isReading) return;
    final coord = context.read<AppCoordinator>();
    // 只有全局阅读会话才由 coordinator 统一结算；初始化局部阅读不走这里。
    if (identical(controller, coord.readingCtrl)) {
      coord.finishReadingSession();
    }
  }

  Future<void> _openOriginal() async {
    final textId = widget.questions.isEmpty ? 0 : widget.questions.first.textId;
    if (textId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开原文：缺少文章信息')),
      );
      return;
    }
    // 用户点击被引导高亮的“原文”按钮即视为已了解该入口，结束引导。
    if (_quizGuideOverlay != null) {
      await _finishQuizGuide();
      if (!mounted) return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReadingPreviewPage(
          textId: textId,
          activeController: widget.readingController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.questions[_index];
    final progress = (_index + 1) / widget.questions.length;

    return Scaffold(
      backgroundColor: context.appColors.paper,
      appBar: AppBar(
        // 合法例外：AppBar 透明背景以露出 Scaffold 纸色。
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.appColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.isInitPart
              ? '初始化答题 · ${widget.articleTitle}'
              : widget.isReview
                  ? '错题复习 · ${widget.articleTitle}'
                  : '随堂练习 · ${widget.articleTitle}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontFamily: AppTheme.fontTitle,
              ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key: _originalButtonKey,
            tooltip: '原文',
            icon: Icon(Icons.menu_book, color: context.appColors.ink),
            onPressed: _openOriginal,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(context.pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '第 ${_index + 1}/${widget.questions.length} 题',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: context.appColors.inkSecondary,
                        ),
                  ),
                  SizedBox(
                    height: context.gapSmall,
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: context.appColors.border,
                      valueColor: AlwaysStoppedAnimation(context.accent),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(context.pagePadding, 0,
                    context.pagePadding, context.pagePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _typeBadge(q),
                    SizedBox(height: context.gapMedium),
                    Text(
                      q.stem,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            height: 1.5,
                          ),
                    ),
                    if (q.context.isNotEmpty) ...[
                      SizedBox(height: context.gapSmall),
                      MarkedSentence(
                        text: q.context,
                        markStart: q.markStart,
                        markLen: q.markLen,
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                              height: 1.5,
                            ),
                      ),
                    ],
                    SizedBox(height: context.gapLg),
                    ...List.generate(4, (i) => _optionTile(q, i)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(context.pagePadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isLast && _unansweredCount > 0) ...[
                    Padding(
                      padding: EdgeInsets.only(bottom: context.gapMedium),
                      child: Text(
                        widget.isInitPart
                            ? '还有 $_unansweredCount 题未作答，可返回补充后再完成本篇'
                            : '还有 $_unansweredCount 题未作答，可返回补充后再提交',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: context.accent,
                            ),
                      ),
                    ),
                  ],
                  Row(
                    children: [
                      if (_index > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _prev,
                            child: const Text('上一题'),
                          ),
                        ),
                      if (_index > 0) SizedBox(width: context.gapMedium),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: context.accent,
                            foregroundColor: context.appColors.onAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          onPressed:
                              _isLast ? (_allowSubmit ? _submit : null) : _next,
                          child: Text(
                            _isLast
                                ? (widget.isInitPart ? '完成本篇' : '提交')
                                : '下一题',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: context.appColors.onAccent,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeBadge(Question q) {
    final isDark = context.select((SettingsController s) => s.darkMode);
    final String label;
    switch (q.qType) {
      case 'shici':
        label = '诗句理解';
        break;
      case 'tongjia':
        label = '通假字';
        break;
      case 'fanyi':
        label = '翻译';
        break;
      case 'xuci':
        label = '虚词';
        break;
      case 'duanju':
        label = '断句';
        break;
      default:
        label = q.qType;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.accent.withAlpha(isDark ? 40 : 20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: context.accent),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: context.accent,
        ),
      ),
    );
  }

  Widget _optionTile(Question q, int i) {
    final isDark = context.select((SettingsController s) => s.darkMode);
    final selected = _choices[_index] == i;
    return Padding(
      padding: EdgeInsets.only(bottom: context.gapMedium),
      child: Material(
        color: selected
            ? context.accent.withAlpha(isDark ? 60 : 24)
            : context.appColors.cardBg,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _selectOption(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: selected ? context.accent : context.appColors.border,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? context.accent
                          : context.appColors.inkSecondary,
                    ),
                    // 合法例外：透明用于未选中选项的圆形占位。
                    color: selected ? context.accent : Colors.transparent,
                  ),
                  child: Text(
                    String.fromCharCode(0x41 + i),
                    style: TextStyle(
                      fontSize: 12,
                      color: selected
                          ? context.appColors.onAccent
                          : context.appColors.inkSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(width: context.gapMedium),
                Expanded(
                  child: Text(
                    q.option(i),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
