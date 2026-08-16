import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/pages/quiz_result_page.dart';
import 'package:chinese_classical_rec_sys/pages/init_result_page.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/marked_sentence.dart';

/// 文章题组答题页：一屏一题，末题提交（题组后统一判分，提交前可回改）
/// [isReview] 错题复习模式：标题区分，提交走复习通道（不产生答题效应）
class QuizPage extends StatefulWidget {
  final String articleTitle;
  final List<Question> questions;
  final bool isReview;
  final bool isInit;

  const QuizPage({
    super.key,
    required this.articleTitle,
    required this.questions,
    this.isReview = false,
    this.isInit = false,
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

  UserController? _userCtrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // dispose 中不可做 ancestor lookup，提前缓存
    _userCtrl ??= context.read<UserController>();
  }

  @override
  void dispose() {
    if (!_ownershipTransferred) {
      _userCtrl?.disposeQuizQuestions(widget.questions);
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // 定长作答数组：前进后退只移动指针，回改不丢后续答案
    _choices = List<int?>.filled(widget.questions.length, null);
  }

  bool get _isLast => _index == widget.questions.length - 1;

  bool get _allowSubmit => _isLast && _choices.every((c) => c != null);

  int get _unansweredCount =>
      widget.questions.length - _choices.where((c) => c != null).length;

  void _selectOption(int opt) {
    setState(() => _choices[_index] = opt);
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
    if (widget.isInit) {
      final ok = userCtrl.applyInit(
        [for (final q in widget.questions) q.id],
        choices,
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('初始化提交失败，请重试')),
        );
        return;
      }
      _ownershipTransferred = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => InitResultPage(questions: widget.questions),
        ),
      );
      return;
    }
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

  @override
  Widget build(BuildContext context) {
    final q = widget.questions[_index];
    final isDark = context.select((SettingsController s) => s.darkMode);
    final progress = (_index + 1) / widget.questions.length;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkPaper : AppTheme.paper,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: isDark ? AppTheme.darkInk : AppTheme.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.isInit
              ? '初始化测验 · ${widget.articleTitle}'
              : widget.isReview
                  ? '错题复习 · ${widget.articleTitle}'
                  : '随堂练习 · ${widget.articleTitle}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontFamily: AppTheme.fontTitle,
              ),
          overflow: TextOverflow.ellipsis,
        ),
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
                          color: isDark
                              ? AppTheme.darkInkSecondary
                              : AppTheme.inkSecondary,
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
                      backgroundColor:
                          isDark ? AppTheme.borderLight : AppTheme.border,
                      valueColor: AlwaysStoppedAnimation(context.accent),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    context.pagePadding, 0, context.pagePadding, context.pagePadding),
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
                        '还有 $_unansweredCount 题未作答，可返回补充后再提交',
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
                            foregroundColor: AppTheme.cardBg,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          onPressed: _isLast
                              ? (_allowSubmit ? _submit : null)
                              : _next,
                          child: Text(
                            _isLast ? '提交' : '下一题',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: AppTheme.cardBg,
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
            : (isDark ? AppTheme.darkCard : AppTheme.cardBg),
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
                color: selected
                    ? context.accent
                    : (isDark ? AppTheme.borderLight : AppTheme.border),
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
                      color: selected ? context.accent : AppTheme.inkSecondary,
                    ),
                    color:
                        selected ? context.accent : Colors.transparent,
                  ),
                  child: Text(
                    String.fromCharCode(0x41 + i),
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? AppTheme.cardBg : AppTheme.inkSecondary,
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
