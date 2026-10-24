import 'package:flutter/material.dart';

import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/spotlight_overlay.dart';

/// 初始化答题页右上角“原文”按钮的一次性引导浮层。
///
/// - 从阅读教程第 4 步真实点击“做题”进入时作为第 5 步展示；
/// - 其他首次进入初始化答题页时作为兜底一次性提示展示。
/// 引导的 seen 标记与插层编排见 `engine/one_shot_guide.dart`。
class InitQuizGuideOverlay extends StatelessWidget {
  final Rect? targetRect;
  final bool isStep5;
  final VoidCallback onSkip;

  const InitQuizGuideOverlay({
    super.key,
    required this.targetRect,
    required this.isStep5,
    required this.onSkip,
  });

  /// 气泡高度估算值（本浮层文案较短）。
  static const double _bubbleEstimatedHeight = 180;

  @override
  Widget build(BuildContext context) {
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
                isStep5 ? '第 5 步' : '提示',
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
            '可回看原文对照',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '返回后答题进度保留',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: onSkip,
              child: const Text('知道了'),
            ),
          ),
        ],
      ),
    );
  }
}
