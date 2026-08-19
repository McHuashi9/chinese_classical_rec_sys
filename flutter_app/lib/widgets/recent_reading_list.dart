import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/service/history_service.dart';
import 'package:chinese_classical_rec_sys/widgets/empty_state.dart';

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
    if (records.isEmpty) {
      return const EmptyState(
        title: '暂无最近阅读',
        subtitle: '读完文章后会出现在这里',
      );
    }

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
                      color: context.appColors.ink,
                    )),
          ),
          Divider(color: context.appColors.border, height: 1),
          ...records.take(10).map((r) => _buildItem(context, r)),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, ReadingRecord r) {
    final dateStr = _formatDate(r.date);
    final minutes = (r.readTime / 60).round();
    return ListTile(
      leading: Icon(Icons.menu_book,
          size: 20, color: context.appColors.inkSecondary),
      title: Text(
        r.title,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.appColors.ink,
              fontWeight: FontWeight.w600,
            ),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${r.author} · $dateStr',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.appColors.inkSecondary,
            ),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text('$minutes 分钟',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: context.appColors.inkSecondary,
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
    final time = _formatTime(date);
    if (diff == 0) return '今天 $time';
    if (diff == 1) return '昨天 $time';
    if (diff <= 7) {
      const days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return '${days[d.weekday - 1]} $time';
    }
    return '${d.month}/${d.day} $time';
  }

  String _formatTime(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(date.hour)}:${two(date.minute)}';
  }
}
