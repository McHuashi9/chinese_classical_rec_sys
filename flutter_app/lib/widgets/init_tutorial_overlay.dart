import 'package:flutter/material.dart';

import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/spotlight_overlay.dart';

/// 初始化第一篇阅读的 3/4 步引导浮层（有初始化题时为 4 步，含“做题”）。
///
/// 遮罩挖洞、输入屏障、气泡卡片与避让由 [SpotlightOverlay] 承担，本类只提供内容。
class InitTutorialOverlay extends StatelessWidget {
  final int step;
  final Rect? targetRect;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  /// 总步数：3 = 无该篇初始化题，4 = 含“做题”步骤。
  final int totalSteps;

  const InitTutorialOverlay({
    super.key,
    required this.step,
    required this.targetRect,
    required this.onNext,
    required this.onSkip,
    this.totalSteps = 4,
  });

  static const List<String> _titles = ['查看注释', '对照译文', '翻页阅读', '开始做题'];
  static const List<String> _messages = [
    '点击带圈数字查看注释',
    '点击这里对照译文',
    '点击翻页继续阅读',
    '阅读时可随时点击“做题”进入本篇初始化题',
  ];

  /// 气泡高度估算值（本浮层正文较长）。
  static const double _bubbleEstimatedHeight = 200;

  @override
  Widget build(BuildContext context) {
    final safeStep =
        step < 0 ? 0 : (step > _titles.length - 1 ? _titles.length - 1 : step);
    final title = _titles[safeStep];
    final message = _messages[safeStep];
    final isLast = safeStep >= totalSteps - 1;

    return SpotlightOverlay(
      targetRect: targetRect,
      bubbleEstimatedHeight: _bubbleEstimatedHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '第 ${step + 1}/$totalSteps 步',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: context.appColors.inkSecondary),
              ),
              const Spacer(),
              TextButton(
                onPressed: onSkip,
                child: const Text('跳过引导'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: context.accent,
                foregroundColor: context.appColors.onAccent,
              ),
              onPressed: onNext,
              child: Text(isLast ? '完成' : '下一步'),
            ),
          ),
        ],
      ),
    );
  }
}
