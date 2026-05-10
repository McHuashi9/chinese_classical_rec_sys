import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/service/history_service.dart';

class StatsCard extends StatelessWidget {
  final ReadingStats stats;
  const StatsCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(context.cardPaddingH),
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.5,
          children: [
            _StatItem(
              label: '总阅读时间',
              value: _formatDuration(stats.totalSeconds),
              isDark: isDark,
            ),
            _StatItem(
              label: '已读篇数',
              value: '${stats.totalTexts} 篇',
              isDark: isDark,
            ),
            _StatItem(
              label: '日均阅读',
              value: '${(stats.dailyAvgSeconds / 60).round()} 分钟',
              isDark: isDark,
            ),
            _StatItem(
              label: '最长连续',
              value: '${stats.longestStreak} 天',
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  const _StatItem({
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.gapSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
              )),
          SizedBox(height: context.gapTiny),
          Text(value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: isDark ? AppTheme.darkInk : AppTheme.ink,
              )),
        ],
      ),
    );
  }
}
