import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 统一空状态占位：几何卷轴图形 + 标题 + 可选副文案/动作。
/// 图标缺失时以几何形 + 文字标注（design-spec），图形取主题强调色、文字取墨色。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size(56, 40),
            painter: _ScrollEmblemPainter(
              accent: theme.colorScheme.primary,
              ink: secondary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(color: secondary),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 几何卷轴：两侧轴头（强调色）+ 卷面（墨色线框 + 三条字行）
class _ScrollEmblemPainter extends CustomPainter {
  final Color accent;
  final Color ink;

  const _ScrollEmblemPainter({required this.accent, required this.ink});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const rollerW = 6.0;

    // 轴头
    final rollerPaint = Paint()..color = accent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, h * 0.12, rollerW, h * 0.76),
          const Radius.circular(2)),
      rollerPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(w - rollerW, h * 0.12, rollerW, h * 0.76),
          const Radius.circular(2)),
      rollerPaint,
    );

    // 卷面
    final face = RRect.fromRectAndRadius(
        Rect.fromLTWH(rollerW * 0.8, h * 0.2, w - rollerW * 1.6, h * 0.6),
        const Radius.circular(2));
    canvas.drawRRect(
      face,
      Paint()
        ..color = accent.withAlpha(20)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      face,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // 三条字行（末行半宽，仿卷轴文末留白）
    final linePaint = Paint()
      ..color = ink.withAlpha(140)
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = h * 0.2 + (i + 1) * h * 0.15;
      final endX = i == 2 ? w * 0.62 : w * 0.78;
      canvas.drawLine(Offset(w * 0.22, y), Offset(endX, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(_ScrollEmblemPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.ink != ink;
}
