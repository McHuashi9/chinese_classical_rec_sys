import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/marked_sentence.dart';

/// 答题结果页：对错统计 + 每题解析 + 能力变化摘要
/// 持有题目列表的内存所有权（QuizPage 提交时转移过来），销毁时统一释放
class QuizResultPage extends StatefulWidget {
  final String articleTitle;
  final List<QuizAnswer> answers;
  final List<Question> questions;

  /// 原题组题数：部分判题失败时 [questions] 只含已生效题目，
  /// 传入原题数以判定"部分失败"（展示时统计仍以已生效题数为准）
  final int totalQuestions;

  /// 错题复习模式：不产生答题效应，摘要文案区分
  final bool isReview;

  const QuizResultPage({
    super.key,
    required this.articleTitle,
    required this.answers,
    required this.questions,
    this.totalQuestions = 0,
    this.isReview = false,
  });

  @override
  State<QuizResultPage> createState() => _QuizResultPageState();
}

class _QuizResultPageState extends State<QuizResultPage> {
  UserController? _userCtrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // dispose 中不可做 ancestor lookup，提前缓存
    _userCtrl ??= context.read<UserController>();
  }

  @override
  void dispose() {
    _userCtrl?.disposeQuizQuestions(widget.questions);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.select((SettingsController s) => s.darkMode);
    final correctCount = widget.answers.where((a) => a.correct).length;
    final total = widget.answers.length;
    // 部分失败判定：显式传入了原题数，且已生效题数不足
    final partial = widget.totalQuestions > 0 &&
        total < widget.totalQuestions;

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
          '答题结果 · ${widget.articleTitle}',
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
                children: [
                  SizedBox(height: context.gapLg),
                  RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.headlineMedium,
                      children: [
                        TextSpan(
                          text: '$correctCount',
                          style: const TextStyle(
                            color: AppTheme.stoneGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(text: ' / $total'),
                      ],
                    ),
                  ),
                  SizedBox(height: context.gapSmall),
                  Text(
                    correctCount == total
                        ? '全部答对，太棒了！'
                        : correctCount >= total / 2
                            ? '表现不错，再接再厉'
                            : '答错较多，可以重读相关段落',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark
                              ? AppTheme.darkInkSecondary
                              : AppTheme.inkSecondary,
                        ),
                  ),
                  SizedBox(height: context.gapSmall),
                  Text(
                    widget.isReview
                        ? '复习不改变能力画像'
                        : partial
                            ? '仅 $total 题计入能力（其余提交失败）'
                            : '能力已随作答更新',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.vermilion,
                        ),
                  ),
                  if (!widget.isReview && correctCount < total) ...[
                    SizedBox(height: context.gapTiny),
                    Text(
                      '错题已入复习队列（约 3 天后到期）',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppTheme.vermilion,
                          ),
                    ),
                  ],
                  SizedBox(height: context.gapLg),
                  const Divider(color: AppTheme.border, height: 1),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(context.pagePadding, 0,
                    context.pagePadding, context.pagePadding),
                itemCount: total,
                itemBuilder: (ctx, i) => _reviewTile(ctx, i, isDark),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(context.pagePadding),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.vermilion,
                    foregroundColor: AppTheme.cardBg,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  child: Text(
                    '返回文库',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppTheme.cardBg,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewTile(BuildContext context, int i, bool isDark) {
    final q = widget.questions[i];
    final a = widget.answers[i];
    final optionChar = String.fromCharCode(0x41 + a.selected);

    return Padding(
      padding: EdgeInsets.only(bottom: context.gapMedium),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : AppTheme.cardBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: a.correct
                ? AppTheme.stoneGreen
                : (isDark ? AppTheme.darkVermilion : AppTheme.vermilion),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  a.correct ? Icons.check_circle : Icons.cancel,
                  size: 18,
                  color: a.correct
                      ? AppTheme.stoneGreen
                      : (isDark ? AppTheme.darkVermilion : AppTheme.vermilion),
                ),
                SizedBox(width: context.gapSmall),
                Expanded(
                  child: Text(
                    '第 ${i + 1} 题',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Text(
                  '你的答案 $optionChar',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isDark
                            ? AppTheme.darkInkSecondary
                            : AppTheme.inkSecondary,
                      ),
                ),
              ],
            ),
            SizedBox(height: context.gapSmall),
            Text(
              q.stem,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.4,
                  ),
            ),
            if (q.context.isNotEmpty) ...[
              SizedBox(height: context.gapTiny),
              MarkedSentence(
                text: q.context,
                markStart: q.markStart,
                markLen: q.markLen,
                isDark: isDark,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      height: 1.4,
                      color: isDark
                          ? AppTheme.darkInkSecondary
                          : AppTheme.inkSecondary,
                    ),
              ),
            ],
            SizedBox(height: context.gapSmall),
            Text(
              '解析：${q.explanation}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                    height: 1.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}