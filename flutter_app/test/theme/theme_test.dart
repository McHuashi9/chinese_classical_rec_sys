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

    test('lightTheme primary 使用自定义 accentColor 原值', () {
      const custom = Color(0xFF000040);
      final theme =
          AppTheme.lightTheme(ScreenSize.medium, 1.0, accentColor: custom);
      expect(theme.colorScheme.primary, custom);
    });

    test('darkTheme 保持暗色亮度且背景不变', () {
      final theme = AppTheme.darkTheme(ScreenSize.medium, 1.0,
          accentColor: const Color(0xFF3A6B8C));
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppTheme.darkPaper);
    });

    test('暗色模式 primary 也使用自定义 accentColor 原值', () {
      const custom = Color(0xFF000040);
      final theme =
          AppTheme.darkTheme(ScreenSize.medium, 1.0, accentColor: custom);
      expect(theme.colorScheme.primary, custom);
    });

    testWidgets('AccentColor 扩展取当前主题 primary', (tester) async {
      const custom = Color(0xFF4A7B6B);
      final theme =
          AppTheme.lightTheme(ScreenSize.medium, 1.0, accentColor: custom);
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

  group('AppColors ThemeExtension', () {
    test('lightTheme 注册 AppColors，error 注入 ColorScheme.error', () {
      const seed = Color(0xFF3A6B8C);
      final theme =
          AppTheme.lightTheme(ScreenSize.medium, 1.0, accentColor: seed);
      final colors = theme.extension<AppColors>();
      expect(colors, isNotNull);
      expect(colors!.paper, AppColors.light.paper);
      expect(colors.cardBg, AppColors.light.cardBg);
      expect(colors.ink, AppColors.light.ink);
      expect(colors.inkSecondary, AppColors.light.inkSecondary);
      expect(colors.border, AppColors.light.border);
      expect(colors.borderLight, AppColors.light.borderLight);
      expect(colors.overlay, AppColors.light.overlay);
      expect(colors.success, AppColors.light.success);
      expect(colors.onAccent, AppColors.light.onAccent);
      expect(colors.error, theme.colorScheme.error);
    });

    test('darkTheme 注册 AppColors，error 注入 ColorScheme.error', () {
      const seed = Color(0xFF3A6B8C);
      final theme =
          AppTheme.darkTheme(ScreenSize.medium, 1.0, accentColor: seed);
      final colors = theme.extension<AppColors>();
      expect(colors, isNotNull);
      expect(colors!.paper, AppColors.dark.paper);
      expect(colors.cardBg, AppColors.dark.cardBg);
      expect(colors.ink, AppColors.dark.ink);
      expect(colors.inkSecondary, AppColors.dark.inkSecondary);
      expect(colors.border, AppColors.dark.border);
      expect(colors.borderLight, AppColors.dark.borderLight);
      expect(colors.overlay, AppColors.dark.overlay);
      expect(colors.success, AppColors.dark.success);
      expect(colors.onAccent, AppColors.dark.onAccent);
      expect(colors.error, theme.colorScheme.error);
    });

    testWidgets('AppColorsX.appColors 取当前主题扩展', (tester) async {
      const seed = Color(0xFF4A7B6B);
      final theme =
          AppTheme.lightTheme(ScreenSize.medium, 1.0, accentColor: seed);
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        }),
      ));
      expect(ctx.appColors, same(theme.extension<AppColors>()));
      expect(ctx.success, ctx.appColors.success);
      expect(ctx.error, theme.colorScheme.error);
    });
  });
}
