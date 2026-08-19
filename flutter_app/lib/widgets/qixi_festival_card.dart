import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/engine/chinese_festivals.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 我的页顶部七夕轻量卡片：仅七夕当天显示，可展开《鹊桥仙·纤云弄巧》节选。
class QixiFestivalCard extends StatefulWidget {
  /// 可注入当前时间便于测试；为空时使用 [DateTime.now]。
  final DateTime? now;

  const QixiFestivalCard({super.key, this.now});

  @override
  State<QixiFestivalCard> createState() => _QixiFestivalCardState();
}

class _QixiFestivalCardState extends State<QixiFestivalCard> {
  static const _poemExcerpt = '纤云弄巧，飞星传恨，银汉迢迢暗度。\n'
      '金风玉露一相逢，便胜却人间无数。\n'
      '柔情似水，佳期如梦，忍顾鹊桥归路。\n'
      '两情若是久长时，又岂在朝朝暮暮。';

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? DateTime.now();
    if (!isQixiToday(now)) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(Icons.favorite, color: context.accent),
        title: const Text('七夕快乐'),
        subtitle: const Text('农历七月初七 · 鹊桥仙·纤云弄巧'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _poemExcerpt,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.7,
                  color: context.appColors.inkSecondary,
                ),
          ),
        ],
      ),
    );
  }
}
