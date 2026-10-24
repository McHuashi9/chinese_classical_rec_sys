import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

void main() {
  const accent = Color(0xFF3A6B8C);
  late ThemeData theme;

  setUp(() {
    theme = AppTheme.lightTheme(
      ScreenSize.medium,
      1.0,
      accentColor: accent,
    );
  });

  test('主按钮主题统一 accent 主色、onAccent 前景、4px 圆角与加粗字重', () {
    final style = theme.filledButtonTheme.style!;

    expect(style.backgroundColor!.resolve(<WidgetState>{}), accent);
    expect(
      style.foregroundColor!.resolve(<WidgetState>{}),
      AppTheme.cardBg,
    );

    final shape =
        style.shape!.resolve(<WidgetState>{})! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(4));

    final textStyle = style.textStyle!.resolve(<WidgetState>{})!;
    expect(textStyle.fontWeight, FontWeight.w600);
    expect(textStyle.fontFamily, AppTheme.fontUI);
    expect(textStyle.fontSize, 14);
  });

  test('主按钮禁用态使用 Material 默认 onSurface 透明度', () {
    final style = theme.filledButtonTheme.style!;
    final disabled = <WidgetState>{WidgetState.disabled};

    expect(
      style.backgroundColor!.resolve(disabled),
      theme.colorScheme.onSurface.withValues(alpha: 0.12),
    );
    expect(
      style.foregroundColor!.resolve(disabled),
      theme.colorScheme.onSurface.withValues(alpha: 0.38),
    );
  });

  testWidgets('FilledButton 实际渲染应用主题主色与圆角', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () {},
            child: const Text('主按钮'),
          ),
        ),
      ),
    ));

    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(FilledButton),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, accent);
    expect(material.shape, isA<RoundedRectangleBorder>());
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(4));
  });

  testWidgets('FilledButton 禁用时渲染主题禁用色', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: const Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: null,
            child: Text('不可用'),
          ),
        ),
      ),
    ));

    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(FilledButton),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(
      material.color,
      theme.colorScheme.onSurface.withValues(alpha: 0.12),
    );
  });
}
