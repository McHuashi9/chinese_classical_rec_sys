import 'package:flutter/material.dart';

import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 初始化第一篇阅读的 3/4 步引导浮层（有初始化题时为 4 步，含“做题”）。
///
/// 自绘实现：半透明遮罩挖出高亮区域，气泡会动态避让高亮目标；
/// 高亮区域本身不遮挡点击，用户可以直接操作被高亮的按钮/注释。
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

  /// 气泡高度估算值，用于决定放在高亮上方还是下方。
  static const double _bubbleEstimatedHeight = 200;
  static const double _edgeGap = 16;
  static const double _targetPadding = 8;

  @override
  Widget build(BuildContext context) {
    final safeStep = step < 0
        ? 0
        : (step > _titles.length - 1 ? _titles.length - 1 : step);
    final title = _titles[safeStep];
    final message = _messages[safeStep];
    final isLast = safeStep >= totalSteps - 1;
    final size = MediaQuery.sizeOf(context);

    return Stack(
      children: [
        // 视觉遮罩只负责“画”，不拦截点击。
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _TutorialHolePainter(
                targetRect: targetRect,
                targetPadding: _targetPadding,
              ),
            ),
          ),
        ),
        // 输入屏障只覆盖高亮区域之外，高亮目标本身可点击。
        ..._buildInputBarriers(size),
        _buildBubble(context, size, title, message, isLast),
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

  Widget _buildBubble(
    BuildContext context,
    Size size,
    String title,
    String message,
    bool isLast,
  ) {
    const left = _edgeGap;
    const right = _edgeGap;
    final card = _buildCard(context, title, message, isLast);

    final target = targetRect;
    if (target == null || target.isEmpty) {
      return Positioned(
        top: MediaQuery.paddingOf(context).top + _edgeGap,
        left: left,
        right: right,
        child: card,
      );
    }

    final hole = target.inflate(_targetPadding);
    final belowTop = hole.bottom + _edgeGap;
    if (belowTop + _bubbleEstimatedHeight <= size.height) {
      return Positioned(
        top: belowTop,
        left: left,
        right: right,
        child: card,
      );
    }

    // 下方放不下时放到高亮上方。
    final aboveBottom = size.height - hole.top + _edgeGap;
    return Positioned(
      bottom: aboveBottom,
      left: left,
      right: right,
      child: card,
    );
  }

  Widget _buildCard(
    BuildContext context,
    String title,
    String message,
    bool isLast,
  ) {
    return Material(
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
      ),
    );
  }
}

class _TutorialHolePainter extends CustomPainter {
  final Rect? targetRect;
  final double targetPadding;

  _TutorialHolePainter({
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
  bool shouldRepaint(covariant _TutorialHolePainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.targetPadding != targetPadding;
  }
}
