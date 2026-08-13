import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/engine/tracker.dart';
import 'package:chinese_classical_rec_sys/pages/quiz_page.dart';
import 'package:chinese_classical_rec_sys/state/coordinator.dart';
import 'package:chinese_classical_rec_sys/state/settings_controller.dart';
import 'package:chinese_classical_rec_sys/state/user_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/empty_state.dart';

/// 错题复习列表页：到期错题按篇分组展示，整篇进入复习页（每组 ≤ quizBatchSize 分批）
class ReviewListPage extends StatefulWidget {
  const ReviewListPage({super.key});

  @override
  State<ReviewListPage> createState() => _ReviewListPageState();
}

class _ReviewListPageState extends State<ReviewListPage> {
  UserController? _userCtrl;
  List<ReviewItem> _due = [];
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _userCtrl ??= context.read<UserController>();
    if (!_loaded) {
      _loaded = true;
      _reload();
    }
  }

  void _reload() {
    setState(() => _due = _userCtrl?.getDueReviews(0) ?? []);
  }

  Future<void> _startGroup(int textId, String title, List<ReviewItem> items) async {
    final userCtrl = _userCtrl!;
    final ids = items.take(KnowledgeTracker.quizBatchSize)
        .map((r) => r.questionId)
        .toList();
    final questions = userCtrl.getQuestionsByIds(ids);
    if (questions.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => QuizPage(
          articleTitle: title,
          questions: questions,
          isReview: true,
        ),
      ),
    );
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.select((SettingsController s) => s.darkMode);
    final coord = context.read<AppCoordinator>();

    // 按篇分组（到期顺序全局排序，组内保序）
    final groups = <int, List<ReviewItem>>{};
    for (final r in _due) {
      groups.putIfAbsent(r.textId, () => []).add(r);
    }

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
          '错题复习',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontFamily: AppTheme.fontTitle,
              ),
        ),
      ),
      body: _due.isEmpty
          ? const EmptyState(
              title: '暂无到期错题',
              subtitle: '答错的题会进入复习队列，约 3 天后到期',
            )
          : ListView(
              padding: EdgeInsets.all(context.pagePadding),
              children: [
                for (final entry in groups.entries)
                  _groupCard(
                    context,
                    isDark,
                    coord.texts.where((t) => t.id == entry.key).firstOrNull?.title,
                    entry.value,
                  ),
              ],
            ),
    );
  }

  Widget _groupCard(BuildContext context, bool isDark, String? title,
      List<ReviewItem> items) {
    final displayTitle = title ?? '文章 #${items.first.textId}';
    return Padding(
      padding: EdgeInsets.only(bottom: context.gapMedium),
      child: Material(
        color: isDark ? AppTheme.darkCard : AppTheme.cardBg,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _startGroup(items.first.textId, displayTitle, items),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isDark ? AppTheme.borderLight : AppTheme.border,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontFamily: AppTheme.fontTitle),
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: context.gapTiny),
                      Text(
                        '${items.length} 道错题到期',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: context.accent,
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 20,
                    color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
