import 'dart:math';
import 'package:flutter/material.dart';

/// 雷达图组件 — CustomPainter (Skia GPU 加速)
/// 等价于 QML AbilityPage 中的 Canvas 雷达图
class RadarChart extends StatelessWidget {
  final List<double> values;
  static const int _dimCount = 10;

  const RadarChart({super.key, required this.values})
      : assert(values.length == _dimCount);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(300, 300),
      painter: _RadarChartPainter(values: values),
    );
  }
}

class _RadarChartPainter extends CustomPainter {
  final List<double> values;
  static const int _n = RadarChart._dimCount;

  _RadarChartPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 20;
    final angleStep = 2 * pi / _n;
    final startAngle = -pi / 2; // 从顶部开始

    // 背景网格
    final gridPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int level = 1; level <= 5; level++) {
      final r = radius * level / 5;
      final path = Path();
      for (int i = 0; i < _n; i++) {
        final angle = startAngle + i * angleStep;
        final p = Offset(
          center.dx + r * cos(angle),
          center.dy + r * sin(angle),
        );
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // 轴线
    for (int i = 0; i < _n; i++) {
      final angle = startAngle + i * angleStep;
      canvas.drawLine(
        center,
        Offset(
          center.dx + radius * cos(angle),
          center.dy + radius * sin(angle),
        ),
        gridPaint,
      );
    }

    // 数据区域
    final dataPath = Path();
    for (int i = 0; i < _n; i++) {
      final angle = startAngle + i * angleStep;
      final r = radius * values[i].clamp(0.0, 1.0);
      final p = Offset(
        center.dx + r * cos(angle),
        center.dy + r * sin(angle),
      );
      if (i == 0) {
        dataPath.moveTo(p.dx, p.dy);
      } else {
        dataPath.lineTo(p.dx, p.dy);
      }
    }
    dataPath.close();

    canvas.drawPath(
      dataPath,
      Paint()
        ..color = Colors.red.shade300.withAlpha(100)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      dataPath,
      Paint()
        ..color = Colors.red.shade400
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 数据点
    for (int i = 0; i < _n; i++) {
      final angle = startAngle + i * angleStep;
      final r = radius * values[i].clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(center.dx + r * cos(angle), center.dy + r * sin(angle)),
        4,
        Paint()..color = Colors.red.shade600,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter oldDelegate) =>
      oldDelegate.values != values;
}
