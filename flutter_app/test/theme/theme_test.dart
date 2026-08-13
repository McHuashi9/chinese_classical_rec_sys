import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

void main() {
  group('AppTheme 自定义主色', () {
    test('lightTheme 以 accentColor 为 seed，纸张色固定', () {
      final theme = AppTheme.lightTheme(ScreenSize.medium, 1.0,
          accentColor: const Color(0xFF3A6B8C));
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, AppTheme.paper);
    });

    test('不同 seed 生成不同 primary', () {
      final a = AppTheme.lightTheme(ScreenSize.medium, 1.0,
          accentColor: const Color(0xFFB33A3A));
      final b = AppTheme.lightTheme(ScreenSize.medium, 1.0,
          accentColor: const Color(0xFF3A6B8C));
      expect(a.colorScheme.primary, isNot(b.colorScheme.primary));
    });

    test('darkTheme 保持暗色亮度且背景不变', () {
      final theme = AppTheme.darkTheme(ScreenSize.medium, 1.0,
          accentColor: const Color(0xFF3A6B8C));
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppTheme.darkPaper);
    });

    test('暗色模式 primary 与亮色不同（同 seed 自动适配）', () {
      const seed = Color(0xFFB33A3A);
      final light = AppTheme.lightTheme(ScreenSize.medium, 1.0,
          accentColor: seed);
      final dark = AppTheme.darkTheme(ScreenSize.medium, 1.0,
          accentColor: seed);
      expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
    });

    testWidgets('AccentColor 扩展取当前主题 primary', (tester) async {
      const custom = Color(0xFF4A7B6B);
      final theme = AppTheme.lightTheme(ScreenSize.medium, 1.0,
          accentColor: custom);
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        }),
      ));
      expect(ctx.accent, theme.colorScheme.primary);
    });
  });
}
