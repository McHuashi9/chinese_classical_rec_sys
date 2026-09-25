import 'dart:math';
import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';

class RadarChart extends StatefulWidget {
  final List<double> targetValues;
  final List<double>? overlayValues;

  const RadarChart({
    super.key,
    required this.targetValues,
    this.overlayValues,
  }) : assert(targetValues.length == abilityCount);

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
    if (oldWidget.targetValues != widget.targetValues ||
        oldWidget.overlayValues != widget.overlayValues) {
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
    final accent = context.accent;
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
        final h =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 400.0;
        return AnimatedBuilder(
          animation: _anim,
          builder: (ctx, _) {
            final colors = context.appColors;
            return CustomPaint(
              size: Size(w, h),
              painter: _RadarChartPainter(
                values: _interpolateValues(widget.targetValues),
                overlayValues: widget.overlayValues != null
                    ? _interpolateValues(widget.overlayValues!)
                    : null,
                labels: abilityLabels,
                progress: _anim.value,
                accentColor: accent,
                borderColor: colors.border,
                borderLightColor: colors.borderLight,
                inkSecondaryColor: colors.inkSecondary,
              ),
            );
          },
        );
      },
    );
  }

  List<double> _interpolateValues(List<double> source) {
    final t = _anim.value;
    return [for (final v in source) (v.clamp(0.0, 1.0) * t)];
  }
}

class _RadarChartPainter extends CustomPainter {
  final List<double> values;
  final List<double>? overlayValues;
  final List<String> labels;
  final double progress;
  final Color accentColor;
  final Color borderColor;
  final Color borderLightColor;
  final Color inkSecondaryColor;

  _RadarChartPainter({
    required this.values,
    this.overlayValues,
    required this.labels,
    required this.progress,
    required this.accentColor,
    required this.borderColor,
    required this.borderLightColor,
    required this.inkSecondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const angleStep = 2 * pi / abilityCount;
    const startAngle = -pi / 2;

    // 轴标签先排版：半径按「最长标签半宽 + 间隙」外扩预留，保证标签既不压在
    // 图形上、也不越出画布（P6-a：真机验收发现「古PPL」等标签压在图上）。
    // 居中排版的段落盒宽恒为 maxWidth，真实文本宽须取 maxIntrinsicWidth。
    const labelGap = 8.0;
    const labelMaxWidth = 72.0;
    final labelPainters = <TextPainter>[];
    final labelHalfWidths = <double>[];
    var maxLabelHalfWidth = 0.0;
    for (final label in labels) {
      final tp = TextPainter(
        text: TextSpan(text: label, style: _labelStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: labelMaxWidth);
      labelPainters.add(tp);
      final halfWidth = min(tp.maxIntrinsicWidth, tp.width) / 2;
      labelHalfWidths.add(halfWidth);
      maxLabelHalfWidth = max(maxLabelHalfWidth, halfWidth);
    }
    final labelOffset = maxLabelHalfWidth + labelGap;
    final radius =
        _resolveRadius(size, labelOffset, labelHalfWidths, labelPainters);
    final labelRadius = radius + labelOffset;

    // grid polygons
    final gridPaint = Paint()
      ..color = borderLightColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int level = 1; level <= 5; level++) {
      final r = radius * level / 5;
      final path = Path();
      for (int i = 0; i < abilityCount; i++) {
        final angle = startAngle + i * angleStep;
        final p =
            Offset(center.dx + r * cos(angle), center.dy + r * sin(angle));
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
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 0; i < abilityCount; i++) {
      final angle = startAngle + i * angleStep;
      canvas.drawLine(
        center,
        Offset(
            center.dx + radius * cos(angle), center.dy + radius * sin(angle)),
        axisPaint,
      );
    }

    // overlay data polygon (difficulty — drawn first so it's behind)
    if (overlayValues != null) {
      final overlayPath = Path();
      for (int i = 0; i < abilityCount; i++) {
        final angle = startAngle + i * angleStep;
        final r = radius * overlayValues![i].clamp(0.0, 1.0);
        final p =
            Offset(center.dx + r * cos(angle), center.dy + r * sin(angle));
        if (i == 0) {
          overlayPath.moveTo(p.dx, p.dy);
        } else {
          overlayPath.lineTo(p.dx, p.dy);
        }
      }
      overlayPath.close();

      // 难度层只描虚线轮廓、不填充，与能力的「填充 + 实线」形成形状/线型双编码
      // （P6-c：仅靠红/灰绿两色区分，色觉障碍用户难分辨）。
      _drawDashedPath(
        canvas,
        overlayPath,
        Paint()
          ..color = AppTheme.stoneGreen
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );

      // overlay data points：空心环点，与能力的实心点成对
      final overlayPointPaint = Paint()
        ..color = AppTheme.stoneGreen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (int i = 0; i < abilityCount; i++) {
        final angle = startAngle + i * angleStep;
        final r = radius * overlayValues![i].clamp(0.0, 1.0);
        canvas.drawCircle(
          Offset(center.dx + r * cos(angle), center.dy + r * sin(angle)),
          3.5,
          overlayPointPaint,
        );
      }
    }

    // main data polygon (ability — drawn on top)
    final dataPath = Path();
    for (int i = 0; i < abilityCount; i++) {
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
        ..color = accentColor.withAlpha(38)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      dataPath,
      Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // data points
    final pointPaint = Paint()..color = accentColor;
    for (int i = 0; i < abilityCount; i++) {
      final angle = startAngle + i * angleStep;
      final r = radius * values[i].clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(center.dx + r * cos(angle), center.dy + r * sin(angle)),
        3,
        pointPaint,
      );
    }

    // axis labels（排版结果复用，圆心距图形 labelOffset，避免压图/越界）
    for (int i = 0; i < abilityCount; i++) {
      final angle = startAngle + i * angleStep;
      final lx = center.dx + labelRadius * cos(angle);
      final ly = center.dy + labelRadius * sin(angle);
      final tp = labelPainters[i];
      tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
    }

    // legend
    if (overlayValues != null) {
      _drawLegend(canvas, size);
    }
  }

  /// 图例标记与实际绘制对齐：能力＝填充多边形，难度＝虚线轮廓（P6-c）。
  void _drawLegend(Canvas canvas, Size size) {
    const legendX = 12.0;
    final legendY = size.height - 20;
    const markerRadius = 5.0;

    // 你的能力：填充多边形 + 实线
    final abilityMarker = _diamond(Offset(legendX, legendY), markerRadius);
    canvas.drawPath(
      abilityMarker,
      Paint()
        ..color = accentColor.withAlpha(38)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      abilityMarker,
      Paint()
        ..color = accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    _drawLegendText(canvas, '你的能力', legendX + 14, legendY);

    // 文章难度：虚线轮廓
    const difficultyX = legendX + 90;
    _drawDashedPath(
      canvas,
      _diamond(Offset(difficultyX, legendY), markerRadius),
      Paint()
        ..color = AppTheme.stoneGreen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
      dash: 3,
      gap: 2.5,
    );
    _drawLegendText(canvas, '文章难度', difficultyX + 14, legendY);
  }

  /// 旋转 45° 的小多边形（菱形）标记路径。
  Path _diamond(Offset center, double radius) {
    return Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius, center.dy)
      ..lineTo(center.dx, center.dy + radius)
      ..lineTo(center.dx - radius, center.dy)
      ..close();
  }

  void _drawLegendText(Canvas canvas, String text, double x, double y) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: _labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x, y - tp.height / 2));
  }

  TextStyle get _labelStyle => TextStyle(
        fontSize: 11,
        fontFamily: AppTheme.fontUI,
        color: inkSecondaryColor,
      );

  /// 由标签盒反推可用半径：标签中心落在 `radius + labelOffset` 处，
  /// 逐轴保证标签文本（|r·cos|+halfW ≤ w/2、|r·sin|+halfH ≤ h/2）不越出画布。
  double _resolveRadius(Size size, double labelOffset,
      List<double> halfWidths, List<TextPainter> painters) {
    final halfWidth = size.width / 2;
    final halfHeight = size.height / 2;
    const angleStep = 2 * pi / abilityCount;
    const startAngle = -pi / 2;
    var radius = min(size.width, size.height) / 2 - labelOffset;
    for (int i = 0; i < abilityCount; i++) {
      final angle = startAngle + i * angleStep;
      final cosA = cos(angle).abs();
      final sinA = sin(angle).abs();
      if (cosA > 1e-6) {
        radius = min(radius, (halfWidth - halfWidths[i]) / cosA - labelOffset);
      }
      if (sinA > 1e-6) {
        radius = min(radius,
            (halfHeight - painters[i].height / 2) / sinA - labelOffset);
      }
    }
    return max(radius, 1.0);
  }

  /// 虚线描边：Flutter Canvas 无原生虚线，按 PathMetric 逐段提取。
  void _drawDashedPath(Canvas canvas, Path path, Paint paint,
      {double dash = 5, double gap = 4}) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter old) =>
      old.progress != progress ||
      old.values != values ||
      old.overlayValues != overlayValues ||
      old.labels != labels ||
      old.accentColor != accentColor ||
      old.borderColor != borderColor ||
      old.borderLightColor != borderLightColor ||
      old.inkSecondaryColor != inkSecondaryColor;
}
