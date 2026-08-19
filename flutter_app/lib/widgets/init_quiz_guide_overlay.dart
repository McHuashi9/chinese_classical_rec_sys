import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 初始化答题页“回看原文”引导是否已展示/跳过的 SharedPreferences 标记。
const String kInitQuizGuideSeenKey = 'init_quiz_guide_seen';

/// 初始化答题页右上角“原文”按钮的一次性引导浮层。
///
/// - 从阅读教程第 4 步真实点击“做题”进入时作为第 5 步展示；
/// - 其他首次进入初始化答题页时作为兜底一次性提示展示。
/// 引导可跳过，完成后写入 [kInitQuizGuideSeenKey]。
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

  static const double _edgeGap = 16;
  static const double _targetPadding = 8;
  static const double _bubbleEstimatedHeight = 180;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _GuideHolePainter(
                targetRect: targetRect,
                targetPadding: _targetPadding,
              ),
            ),
          ),
        ),
        ..._buildInputBarriers(size),
        _buildBubble(context, size),
      ],
    );
  }

  List<Widget> _buildInputBarriers(Size size) {
    final target = targetRect;
    if (target == null || target.isEmpty) {
      return [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: const SizedBox.expand(),
          ),
        ),
      ];
    }

    final hole = target.inflate(_targetPadding);
    final widgets = <Widget>[];

    void addBarrier(Rect rect) {
      if (rect.isEmpty || rect.width <= 0 || rect.height <= 0) return;
      widgets.add(
        Positioned.fromRect(
          rect: rect,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: const SizedBox.expand(),
          ),
        ),
      );
    }

    addBarrier(Rect.fromLTRB(0, 0, size.width, hole.top));
    addBarrier(Rect.fromLTRB(0, hole.bottom, size.width, size.height));
    addBarrier(Rect.fromLTRB(0, hole.top, hole.left, hole.bottom));
    addBarrier(Rect.fromLTRB(hole.right, hole.top, size.width, hole.bottom));
    return widgets;
  }

  Widget _buildBubble(BuildContext context, Size size) {
    final card = Material(
      color: context.appColors.cardBg,
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                style: FilledButton.styleFrom(
                  backgroundColor: context.accent,
                  foregroundColor: context.appColors.onAccent,
                ),
                onPressed: onSkip,
                child: const Text('知道了'),
              ),
            ),
          ],
        ),
      ),
    );

    final target = targetRect;
    if (target == null || target.isEmpty) {
      return Positioned(
        top: MediaQuery.paddingOf(context).top + _edgeGap,
        left: _edgeGap,
        right: _edgeGap,
        child: card,
      );
    }

    final hole = target.inflate(_targetPadding);
    final belowTop = hole.bottom + _edgeGap;
    if (belowTop + _bubbleEstimatedHeight <= size.height) {
      return Positioned(
        top: belowTop,
        left: _edgeGap,
        right: _edgeGap,
        child: card,
      );
    }

    final aboveBottom = size.height - hole.top + _edgeGap;
    return Positioned(
      bottom: aboveBottom,
      left: _edgeGap,
      right: _edgeGap,
      child: card,
    );
  }
}

class _GuideHolePainter extends CustomPainter {
  final Rect? targetRect;
  final double targetPadding;

  _GuideHolePainter({
    required this.targetRect,
    required this.targetPadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final full = Rect.fromLTWH(0, 0, size.width, size.height);
    final dimPaint = Paint()..color = Colors.black54;

    final target = targetRect;
    if (target == null || target.isEmpty) {
      canvas.drawRect(full, dimPaint);
      return;
    }

    final hole = target.inflate(targetPadding);
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(full),
      Path()..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(8))),
    );
    canvas.drawPath(path, dimPaint);

    canvas.drawRRect(
      RRect.fromRectAndRadius(hole, const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _GuideHolePainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.targetPadding != targetPadding;
  }
}
