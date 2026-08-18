import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/models/question.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/marked_sentence.dart';

/// 从解析文案“正确答案：X。”中解析正确选项下标。
/// 优先支持“正确答案：B。”这类字母写法；真实数据为“正确答案：<选项文本>。”，
/// 因此再按选项文本在“正确答案：”后最早出现的位置匹配。
final RegExp _correctAnswerPattern = RegExp(r'正确答案[:：]\s*([A-D])');
final RegExp _correctAnswerMarkerPattern = RegExp(r'正确答案[:：]\s*');

int? _correctOptionIndex(Question q) {
  final explanation = q.explanation;
  final letterMatch = _correctAnswerPattern.firstMatch(explanation);
  if (letterMatch != null) {
    return letterMatch.group(1)!.codeUnitAt(0) - 0x41;
  }
  final markerMatch = _correctAnswerMarkerPattern.firstMatch(explanation);
  if (markerMatch == null) return null;
  final rest = explanation.substring(markerMatch.end);
  int? bestIndex;
  var bestStart = -1;
  var bestLen = -1;
  for (var i = 0; i < 4; i++) {
    final option = q.option(i).trim();
    if (option.isEmpty) continue;
    final start = rest.indexOf(option);
    if (start < 0) continue;
    if (bestIndex == null ||
        start < bestStart ||
        (start == bestStart && option.length > bestLen)) {
      bestIndex = i;
      bestStart = start;
      bestLen = option.length;
    }
  }
  return bestIndex;
}

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
                          color: context.accent,
                        ),
                  ),
                  if (!widget.isReview && correctCount < total) ...[
                    SizedBox(height: context.gapTiny),
                    Text(
                      '错题已入复习队列（约 3 天后到期）',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: context.accent,
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
                    backgroundColor: context.accent,
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
    final correctIndex = _correctOptionIndex(q);

    return Padding(
      padding: EdgeInsets.only(bottom: context.gapMedium),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : AppTheme.cardBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: a.correct ? AppTheme.stoneGreen : context.accent,
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
                      : context.accent,
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
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      height: 1.4,
                      color: isDark
                          ? AppTheme.darkInkSecondary
                          : AppTheme.inkSecondary,
                    ),
              ),
            ],
            SizedBox(height: context.gapSmall),
            for (var idx = 0; idx < 4; idx++) ...[
              if (q.option(idx).isNotEmpty) ...[
                _OptionTile(
                  label: String.fromCharCode(0x41 + idx),
                  text: q.option(idx),
                  isSelected: idx == a.selected,
                  isCorrect: idx == correctIndex,
                  isDark: isDark,
                ),
                if (idx < 3) SizedBox(height: context.gapTiny),
              ],
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

class _OptionTile extends StatelessWidget {
  final String label;
  final String text;
  final bool isSelected;
  final bool isCorrect;
  final bool isDark;

  const _OptionTile({
    required this.label,
    required this.text,
    required this.isSelected,
    required this.isCorrect,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final Color borderColor;
    final Color? bgColor;
    if (isSelected) {
      borderColor = isCorrect ? AppTheme.stoneGreen : context.accent;
      bgColor = (isCorrect ? AppTheme.stoneGreen : context.accent)
          .withAlpha(isDark ? 30 : 15);
    } else if (isCorrect) {
      borderColor = AppTheme.stoneGreen;
      bgColor = null;
    } else {
      borderColor = isDark ? AppTheme.borderLight : AppTheme.border;
      bgColor = null;
    }
    final textColor = isDark ? AppTheme.darkInk : AppTheme.ink;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Text(
            '$label.',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: borderColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: textColor, height: 1.3),
            ),
          ),
          if (isSelected) ...[
            const SizedBox(width: 8),
            Text(
              '你的选择',
              style: TextStyle(fontSize: 12, color: borderColor),
            ),
          ],
          if (isCorrect) ...[
            const SizedBox(width: 4),
            const Icon(Icons.check_circle, size: 16, color: AppTheme.stoneGreen),
          ],
        ],
      ),
    );
  }
}
