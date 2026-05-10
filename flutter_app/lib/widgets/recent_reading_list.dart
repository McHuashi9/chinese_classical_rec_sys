import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/service/history_service.dart';

class RecentReadingList extends StatelessWidget {
  final List<ReadingRecord> records;
  final void Function(int textId)? onTap;

  const RecentReadingList({
    super.key,
    required this.records,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.cardPaddingH,
              context.cardPaddingV,
              context.cardPaddingH,
              0,
            ),
            child: Text('最近阅读',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: isDark ? AppTheme.darkInk : AppTheme.ink,
                )),
          ),
          const Divider(color: AppTheme.border, height: 1),
          ...records.take(10).map((r) => _buildItem(context, r, isDark)),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, ReadingRecord r, bool isDark) {
    final dateStr = _formatDate(r.date);
    final minutes = (r.readTime / 60).round();
    return ListTile(
      leading: Icon(Icons.menu_book, size: 20,
        color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary),
      title: Text('${r.title} · ${r.author}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isDark ? AppTheme.darkInk : AppTheme.ink,
          ),
          overflow: TextOverflow.ellipsis),
      trailing: Text('$minutes 分钟',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
          )),
      subtitle: Text(dateStr,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
          )),
      dense: true,
      onTap: onTap != null ? () => onTap!(r.textId) : null,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff <= 7) {
      const days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return days[d.weekday - 1];
    }
    return '${d.month}/${d.day}';
  }
}
