import 'dart:math';
import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

const _dimLabels = [
  '平均句长',
  '句子数量',
  '虚词比例',
  '字频对数',
  '通假密度',
  '古PPL',
  '现PPL',
  'MATTR',
  '典故密度',
  '语义复杂度',
];
const int _dimCount = 10;

class RadarChart extends StatefulWidget {
  final List<double> targetValues;

  const RadarChart({super.key, required this.targetValues})
      : assert(targetValues.length == _dimCount);

  @override
  State<RadarChart> createState() => _RadarChartState();
}

class _RadarChartState extends State<RadarChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _anim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _animCtrl.forward(from: 0);
  }

  @override
  void didUpdateWidget(RadarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetValues != widget.targetValues) {
      _animCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 400.0;
        return AnimatedBuilder(
          animation: _anim,
          builder: (ctx, _) {
            return CustomPaint(
              size: Size(w, h),
              painter: _RadarChartPainter(
                values: _interpolateValues(),
                labels: _dimLabels,
                progress: _anim.value,
              ),
            );
          },
        );
      },
    );
  }

  List<double> _interpolateValues() {
    final t = _anim.value;
    final result = <double>[];
    for (int i = 0; i < _dimCount; i++) {
      final target = widget.targetValues[i].clamp(0.0, 1.0);
      result.add(target * t);
    }
    return result;
  }
}

class _RadarChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final double progress;

  _RadarChartPainter({
    required this.values,
    required this.labels,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 42;
    const angleStep = 2 * pi / _dimCount;
    const startAngle = -pi / 2;

    // grid polygons
    final gridPaint = Paint()
      ..color = AppTheme.borderLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int level = 1; level <= 5; level++) {
      final r = radius * level / 5;
      final path = Path();
      for (int i = 0; i < _dimCount; i++) {
        final angle = startAngle + i * angleStep;
        final p = Offset(center.dx + r * cos(angle), center.dy + r * sin(angle));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // axis lines
    final axisPaint = Paint()
      ..color = AppTheme.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 0; i < _dimCount; i++) {
      final angle = startAngle + i * angleStep;
      canvas.drawLine(
        center,
        Offset(center.dx + radius * cos(angle), center.dy + radius * sin(angle)),
        axisPaint,
      );
    }

    // data polygon fill
    final dataPath = Path();
    for (int i = 0; i < _dimCount; i++) {
      final angle = startAngle + i * angleStep;
      final r = radius * values[i].clamp(0.0, 1.0);
      final p = Offset(center.dx + r * cos(angle), center.dy + r * sin(angle));
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
        ..color = AppTheme.vermilion.withAlpha(38)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      dataPath,
      Paint()
        ..color = AppTheme.vermilion
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // data points
    final pointPaint = Paint()..color = AppTheme.vermilion;
    for (int i = 0; i < _dimCount; i++) {
      final angle = startAngle + i * angleStep;
      final r = radius * values[i].clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(center.dx + r * cos(angle), center.dy + r * sin(angle)),
        3,
        pointPaint,
      );
    }

    // axis labels
    final labelRadius = radius + 18;
    for (int i = 0; i < _dimCount; i++) {
      final angle = startAngle + i * angleStep;
      final lx = center.dx + labelRadius * cos(angle);
      final ly = center.dy + labelRadius * sin(angle);

      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: const TextStyle(
            fontSize: 11,
            fontFamily: AppTheme.fontUI,
            color: AppTheme.inkSecondary,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: 72);

      tp.paint(
        canvas,
        Offset(lx - tp.width / 2, ly - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter old) =>
      old.progress != progress || old.values != values || old.labels != labels;
}
