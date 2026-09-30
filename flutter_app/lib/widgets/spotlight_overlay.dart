import 'package:flutter/material.dart';

import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 取 [key] 关联 RenderBox 的全局矩形；未挂载或非 RenderBox 时返回 null。
///
/// 引导浮层用它把高亮目标（按钮/正文）的屏幕坐标交给 [SpotlightOverlay]。
Rect? rectOfKey(GlobalKey key) {
  final ctx = key.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject();
  if (box is! RenderBox) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// 一次性引导浮层的通用外壳：遮罩挖洞 + 输入屏障 + 气泡卡片与上下避让。
///
/// - 视觉遮罩在高亮目标（[targetRect] 外扩 [targetPadding]）处挖洞，只负责“画”；
/// - 输入屏障只覆盖高亮区域之外，高亮目标本身仍可点击；
/// - [child] 为气泡内容，由本组件套上统一卡片外观（底色/圆角/elevation/内边距），
///   并按 [bubbleEstimatedHeight] 判断放在高亮目标的下方还是上方。
class SpotlightOverlay extends StatelessWidget {
  final Rect? targetRect;
  final double targetPadding;

  /// 气泡高度估算值，用于决定放在高亮上方还是下方。
  final double bubbleEstimatedHeight;

  /// 气泡内容（标签行 / 标题 / 正文 / 按钮由调用方给出）。
  final Widget child;

  const SpotlightOverlay({
    super.key,
    required this.targetRect,
    this.targetPadding = 8,
    required this.bubbleEstimatedHeight,
    required this.child,
  });

  static const double _edgeGap = 16;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // 气泡统一卡片外观：各引导浮层只提供内容，保证视觉不漂移。
    final bubble = Material(
      color: context.appColors.cardBg,
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );

    return Stack(
      children: [
        // 视觉遮罩只负责“画”，不拦截点击。
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _HolePainter(
                targetRect: targetRect,
                targetPadding: targetPadding,
              ),
            ),
          ),
        ),
        // 输入屏障只覆盖高亮区域之外，高亮目标本身可点击。
        ..._buildInputBarriers(size),
        _positionBubble(context, size, bubble),
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

    final hole = target.inflate(targetPadding);
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

  Widget _positionBubble(BuildContext context, Size size, Widget bubble) {
    const left = _edgeGap;
    const right = _edgeGap;

    final target = targetRect;
    if (target == null || target.isEmpty) {
      return Positioned(
        top: MediaQuery.paddingOf(context).top + _edgeGap,
        left: left,
        right: right,
        child: bubble,
      );
    }

    final hole = target.inflate(targetPadding);
    final belowTop = hole.bottom + _edgeGap;
    if (belowTop + bubbleEstimatedHeight <= size.height) {
      return Positioned(
        top: belowTop,
        left: left,
        right: right,
        child: bubble,
      );
    }

    // 下方放不下时放到高亮上方。
    final aboveBottom = size.height - hole.top + _edgeGap;
    return Positioned(
      bottom: aboveBottom,
      left: left,
      right: right,
      child: bubble,
    );
  }
}

class _HolePainter extends CustomPainter {
  final Rect? targetRect;
  final double targetPadding;

  _HolePainter({
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
  bool shouldRepaint(covariant _HolePainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.targetPadding != targetPadding;
  }
}
