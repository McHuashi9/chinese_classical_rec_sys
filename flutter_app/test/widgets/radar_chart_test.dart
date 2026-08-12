import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/models/user.dart';
import 'package:chinese_classical_rec_sys/widgets/radar_chart.dart';

void main() {
  Widget wrap(RadarChart chart) =>
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
}
