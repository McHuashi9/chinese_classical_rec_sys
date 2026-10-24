import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/dimension_bar.dart';

void main() {
  const color = Color(0xFF5B7B4A);

  Future<void> pumpBar(
    WidgetTester tester, {
    double value = 0.42,
    double labelWidth = 76,
  }) async {
    final theme = AppTheme.lightTheme(
      ScreenSize.medium,
      1.0,
      accentColor: AppTheme.vermilion,
    );
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 500,
            child: DimensionBar(
              label: '平均句长',
              value: value,
              color: color,
              labelWidth: labelWidth,
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('渲染标签、百分比、颜色与标签宽度', (tester) async {
    await pumpBar(tester);
    await tester.pumpAndSettle();

    expect(find.text('平均句长'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);

    final labelBox = tester.widget<SizedBox>(
      find
          .ancestor(
            of: find.text('平均句长'),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(labelBox.width, 76);

    final track = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(ClipRRect),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(track.color, color.withAlpha(31));
  });

  testWidgets('数值 clamp 到 0..1，并使用 300ms easeOutCubic', (tester) async {
    await pumpBar(tester, value: 1.4);

    final animated = tester.widget<TweenAnimationBuilder<double>>(
      find.byType(TweenAnimationBuilder<double>),
    );
    expect(animated.tween.begin, 0);
    expect(animated.tween.end, 1.0);
    expect(animated.duration, const Duration(milliseconds: 300));
    expect(animated.curve, Curves.easeOutCubic);

    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    final fraction = tester.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    expect(fraction.widthFactor, 1.0);
  });

  testWidgets('标签宽度可按页面参数覆盖', (tester) async {
    await pumpBar(tester, labelWidth: 130);
    await tester.pumpAndSettle();

    final labelBox = tester.widget<SizedBox>(
      find
          .ancestor(
            of: find.text('平均句长'),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(labelBox.width, 130);
  });
}
