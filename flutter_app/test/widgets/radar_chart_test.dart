import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/radar_chart.dart';

/// 只记录断言需要的两类绘制调用，其余转发空实现（`noSuchMethod`）。
class _RecordingCanvas implements Canvas {
  final paragraphs = <(ui.Paragraph, Offset)>[];
  final pathPaints = <Paint>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    paragraphs.add((paragraph, offset));
  }

  @override
  void drawPath(Path path, Paint paint) {
    pathPaints.add(paint);
  }

  @override
  void noSuchMethod(Invocation invocation) {}
}

void main() {
  Widget wrap(Widget chart) =>
      MaterialApp(home: Scaffold(body: Center(child: chart)));

  testWidgets('渲染十维雷达图（CustomPaint），动画完成后不崩', (tester) async {
    await tester.pumpWidget(
      wrap(RadarChart(targetValues: List.filled(abilityCount, 0.5))),
    );
    expect(find.byType(CustomPaint), findsWidgets);
    // 动画持续 500ms，走完不抛错
    await tester.pumpAndSettle();
  });

  testWidgets('带 overlay 对比值时正常渲染', (tester) async {
    await tester.pumpWidget(wrap(RadarChart(
      targetValues: List.filled(abilityCount, 0.5),
      overlayValues: List.filled(abilityCount, 0.3),
    )));
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.pumpAndSettle();
  });

  testWidgets('维度数与 abilityCount 不符时断言失败', (tester) async {
    expect(
      () => RadarChart(targetValues: List.filled(abilityCount - 1, 0.5)),
      throwsAssertionError,
    );
  });

  testWidgets('数值越界（>1）也能渲染（不抛错）', (tester) async {
    await tester.pumpWidget(
      wrap(RadarChart(targetValues: List.filled(abilityCount, 1.5))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('窄画布下轴标签与图例不越界，难度层不再填充（P6-a/P6-c 回归）',
      (tester) async {
    const size = Size(280, 250);
    await tester.pumpWidget(wrap(SizedBox(
      width: size.width,
      height: size.height,
      child: RadarChart(
        targetValues: List.filled(abilityCount, 0.5),
        overlayValues: List.filled(abilityCount, 0.5),
      ),
    )));
    await tester.pumpAndSettle();

    final cp = tester.widget<CustomPaint>(find.descendant(
      of: find.byType(RadarChart),
      matching: find.byType(CustomPaint),
    ));
    final canvas = _RecordingCanvas();
    cp.painter!.paint(canvas, size);

    // 10 个轴标签 + 2 个图例文字
    expect(canvas.paragraphs.length, abilityCount + 2);
    for (final (paragraph, offset) in canvas.paragraphs.take(abilityCount)) {
      // 居中排版的段落盒宽恒为 maxWidth，可见文本居中 → 按文本实际范围断言
      final boxWidth = paragraph.width;
      final textWidth = min(paragraph.maxIntrinsicWidth, boxWidth);
      final left = offset.dx + (boxWidth - textWidth) / 2;
      expect(left, greaterThanOrEqualTo(-0.01));
      expect(offset.dy, greaterThanOrEqualTo(-0.01));
      expect(left + textWidth, lessThanOrEqualTo(size.width + 0.01));
      expect(
          offset.dy + paragraph.height, lessThanOrEqualTo(size.height + 0.01));
    }

    // 难度层＝虚线轮廓，不再使用石绿填充
    expect(
      canvas.pathPaints.where((p) =>
          p.style == PaintingStyle.fill &&
          p.color == AppTheme.stoneGreen.withAlpha(38)),
      isEmpty,
    );
  });
}
