import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 能力维度 / 阅读收益共用的水平进度条。
///
/// 调用方只负责提供文案、数值、颜色和标签宽度；动画时长与曲线统一在这里，
/// 避免我的页与文章详情页再次出现“一处有动画、一处没有”的分叉。
class DimensionBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final double labelWidth;
  final Duration duration;
  final Curve curve;

  const DimensionBar({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.labelWidth,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeOutCubic,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    final pct = (clamped * 100).toStringAsFixed(0);

    return Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: context.appColors.inkSecondary,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: context.gapMedium),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Container(
              height: 10,
              color: color.withAlpha(31),
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: clamped),
                duration: duration,
                curve: curve,
                builder: (ctx, animatedValue, child) => FractionallySizedBox(
                  widthFactor: animatedValue,
                  child: child,
                ),
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: context.gapMedium),
        SizedBox(
          width: 48,
          child: Text(
            '$pct%',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.appColors.inkSecondary,
                ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
