import 'package:flutter/material.dart';

enum ScreenSize { small, medium, large }

/// 设计系统 Token → Flutter ThemeData
/// 颜色/字体/间距严格对齐 design-spec.md
class AppTheme {
  AppTheme._();

  // ─── 颜色 Token ────────────────────────────────────────────────

  static const Color paper = Color(0xFFF5F0E8);
  static const Color cardBg = Color(0xFFFFFDF7);
  static const Color ink = Color(0xFF2C2416);
  static const Color inkSecondary = Color(0xFF5A5245);

  /// 强调色默认值（朱砂红）；用户可在设置页自定义主色，
  /// 实际生效值一律从 [AccentColor.accent] 取（ColorScheme.primary）
  static const Color vermilion = Color(0xFFB33A3A);
  static const Color stoneGreen = Color(0xFF5B7B4A);
  static const Color border = Color(0xFFC2B28F);
  static const Color borderLight = Color(0xFFD4C9A8);
  static const Color overlay = Color(0xCC1C1812);

  static const Color darkPaper = Color(0xFF1C1812);
  static const Color darkCard = Color(0xFF2A251D);
  static const Color darkInk = Color(0xFFD4C9A8);
  static const Color darkInkSecondary = Color(0xFF9A9278);

  /// 档案头像色板（按档案 id 稳定分配；与设置页主题色预设共用同一组传统色）
  static const List<Color> profileAvatarColors = <Color>[
    Color(0xFFB33A3A), // 朱砂
    Color(0xFF5B7B4A), // 石绿
    Color(0xFF3A6B8C), // 靛蓝
    Color(0xFF8B5E3C), // 赭石
    Color(0xFF6B4E71), // 紫檀
    Color(0xFF4A7B6B), // 松花绿
    Color(0xFF3A4E6B), // 黛蓝
    Color(0xFF7B3A55), // 绛紫
    Color(0xFFA87E2B), // 藤黄
    Color(0xFF4E7B5B), // 竹青
    Color(0xFF2F4B66), // 藏青
    Color(0xFF9C3A55), // 胭脂
  ];

  // ─── 字体 ─────────────────────────────────────────────────────

  static const String fontTitle = 'LXGWWenKai';
  static const String fontBody = 'SourceHanSerifSC';
  static const String fontUI = 'HarmonyOSSansSC';

  // ─── 断点 ─────────────────────────────────────────────────────

  static const double breakSmall = 600;
  static const double breakLarge = 1200;

  static ScreenSize screenSizeForWidth(double w) {
    return w < breakSmall
        ? ScreenSize.small
        : w < breakLarge
            ? ScreenSize.medium
            : ScreenSize.large;
  }

  // ─── 响应式字号 ───────────────────────────────────────────────

  static double _headlineLarge(ScreenSize size) => switch (size) {
        ScreenSize.small => 24,
        ScreenSize.medium => 28,
        ScreenSize.large => 36,
      };

  static double _headlineMedium(ScreenSize size) => switch (size) {
        ScreenSize.small => 20,
        ScreenSize.medium => 22,
        ScreenSize.large => 24,
      };

  static double _titleLarge(ScreenSize size) => switch (size) {
        ScreenSize.small => 18,
        ScreenSize.medium => 19,
        ScreenSize.large => 20,
      };

  static double _bodyLarge(ScreenSize size) => switch (size) {
        ScreenSize.small => 15,
        ScreenSize.medium => 16,
        ScreenSize.large => 16,
      };

  static TextStyle bodyReadingSize(ScreenSize size, double fontScale) =>
      TextStyle(
        fontSize: switch (size) {
              ScreenSize.small => 15,
              ScreenSize.medium => 16,
              ScreenSize.large => 18,
            } *
            fontScale,
        fontFamily: fontBody,
        height: 1.8,
      );

  // ─── Light Theme ──────────────────────────────────────────────

  static ThemeData lightTheme(ScreenSize size, double fontScale,
      {required Color accentColor}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: Brightness.light,
      surface: paper,
    ).copyWith(primary: accentColor);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      extensions: [AppColors.light.copyWith(error: scheme.error)],
      scaffoldBackgroundColor: paper,
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: border, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        clipBehavior: Clip.antiAlias,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
            fontSize: _headlineLarge(size) * fontScale,
            fontFamily: fontTitle,
            color: ink),
        headlineMedium: TextStyle(
            fontSize: _headlineMedium(size) * fontScale,
            fontFamily: fontTitle,
            color: ink),
        headlineSmall: TextStyle(
            fontSize: 22 * fontScale, fontFamily: fontTitle, color: ink),
        titleLarge: TextStyle(
            fontSize: _titleLarge(size) * fontScale,
            fontFamily: fontTitle,
            color: ink),
        titleMedium: TextStyle(
            fontSize: 16 * fontScale, fontFamily: fontTitle, color: ink),
        titleSmall: TextStyle(
            fontSize: 14 * fontScale, fontFamily: fontUI, color: inkSecondary),
        bodyLarge: TextStyle(
            fontSize: _bodyLarge(size) * fontScale,
            fontFamily: fontBody,
            color: ink,
            height: 2.0),
        bodyMedium: TextStyle(
            fontSize: 14 * fontScale, fontFamily: fontUI, color: inkSecondary),
        bodySmall: TextStyle(
            fontSize: 12 * fontScale, fontFamily: fontUI, color: inkSecondary),
        labelLarge: TextStyle(
            fontSize: 14 * fontScale, fontFamily: fontUI, color: inkSecondary),
        labelSmall: TextStyle(
            fontSize: 12 * fontScale, fontFamily: fontUI, color: inkSecondary),
      ),
    );
  }

  // ─── Dark Theme ───────────────────────────────────────────────

  static ThemeData darkTheme(ScreenSize size, double fontScale,
      {required Color accentColor}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: Brightness.dark,
      surface: darkPaper,
    ).copyWith(primary: accentColor);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      extensions: [AppColors.dark.copyWith(error: scheme.error)],
      scaffoldBackgroundColor: darkPaper,
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: borderLight, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        clipBehavior: Clip.antiAlias,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkPaper,
        foregroundColor: darkInk,
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
            fontSize: _headlineLarge(size) * fontScale,
            fontFamily: fontTitle,
            color: darkInk),
        headlineMedium: TextStyle(
            fontSize: _headlineMedium(size) * fontScale,
            fontFamily: fontTitle,
            color: darkInk),
        headlineSmall: TextStyle(
            fontSize: 22 * fontScale, fontFamily: fontTitle, color: darkInk),
        titleLarge: TextStyle(
            fontSize: _titleLarge(size) * fontScale,
            fontFamily: fontTitle,
            color: darkInk),
        titleMedium: TextStyle(
            fontSize: 16 * fontScale, fontFamily: fontTitle, color: darkInk),
        titleSmall: TextStyle(
            fontSize: 14 * fontScale,
            fontFamily: fontUI,
            color: darkInkSecondary),
        bodyLarge: TextStyle(
            fontSize: _bodyLarge(size) * fontScale,
            fontFamily: fontBody,
            color: darkInk,
            height: 2.0),
        bodyMedium: TextStyle(
            fontSize: 14 * fontScale,
            fontFamily: fontUI,
            color: darkInkSecondary),
        bodySmall: TextStyle(
            fontSize: 12 * fontScale,
            fontFamily: fontUI,
            color: darkInkSecondary),
        labelLarge: TextStyle(
            fontSize: 14 * fontScale,
            fontFamily: fontUI,
            color: darkInkSecondary),
        labelSmall: TextStyle(
            fontSize: 12 * fontScale,
            fontFamily: fontUI,
            color: darkInkSecondary),
      ),
    );
  }
}

/// 亮/暗语义色。页面 UI 取色一律通过 [AppColorsX.appColors]，
/// [AppTheme] 静态常量只作为原始色值来源 / 非 UI 默认值 / 测试使用。
class AppColors extends ThemeExtension<AppColors> {
  final Color paper;
  final Color cardBg;
  final Color ink;
  final Color inkSecondary;
  final Color border;
  final Color borderLight;
  final Color overlay;
  final Color success;
  final Color error;

  /// 强调色填充按钮/图标上的前景色（亮暗都保持亮米色，保证对比度）。
  final Color onAccent;

  const AppColors({
    required this.paper,
    required this.cardBg,
    required this.ink,
    required this.inkSecondary,
    required this.border,
    required this.borderLight,
    required this.overlay,
    required this.success,
    required this.error,
    required this.onAccent,
  });

  /// 亮色默认语义色；正式 ThemeData 中 error 会用 ColorScheme.error 覆盖。
  static const AppColors light = AppColors(
    paper: AppTheme.paper,
    cardBg: AppTheme.cardBg,
    ink: AppTheme.ink,
    inkSecondary: AppTheme.inkSecondary,
    border: AppTheme.border,
    borderLight: AppTheme.borderLight,
    overlay: AppTheme.overlay,
    success: AppTheme.stoneGreen,
    error: _lightError,
    onAccent: AppTheme.cardBg,
  );

  /// 暗色默认语义色；正式 ThemeData 中 error 会用 ColorScheme.error 覆盖。
  static const AppColors dark = AppColors(
    paper: AppTheme.darkPaper,
    cardBg: AppTheme.darkCard,
    ink: AppTheme.darkInk,
    inkSecondary: AppTheme.darkInkSecondary,
    border: AppTheme.borderLight,
    borderLight: AppTheme.borderLight,
    overlay: AppTheme.overlay,
    success: AppTheme.stoneGreen,
    error: _darkError,
    onAccent: AppTheme.cardBg,
  );

  static const Color _lightError = Color(0xFFB3261E);
  static const Color _darkError = Color(0xFFF2B8B5);

  @override
  AppColors copyWith({
    Color? paper,
    Color? cardBg,
    Color? ink,
    Color? inkSecondary,
    Color? border,
    Color? borderLight,
    Color? overlay,
    Color? success,
    Color? error,
    Color? onAccent,
  }) {
    return AppColors(
      paper: paper ?? this.paper,
      cardBg: cardBg ?? this.cardBg,
      ink: ink ?? this.ink,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      border: border ?? this.border,
      borderLight: borderLight ?? this.borderLight,
      overlay: overlay ?? this.overlay,
      success: success ?? this.success,
      error: error ?? this.error,
      onAccent: onAccent ?? this.onAccent,
    );
  }

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      paper: Color.lerp(paper, other.paper, t)!,
      cardBg: Color.lerp(cardBg, other.cardBg, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSecondary: Color.lerp(inkSecondary, other.inkSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderLight: Color.lerp(borderLight, other.borderLight, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
    );
  }
}

/// 页面取色入口：亮/暗语义色统一从 [AppColors] 扩展获取。
extension AppColorsX on BuildContext {
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? AppColors.dark
          : AppColors.light);

  Color get success => appColors.success;

  Color get error => Theme.of(this).colorScheme.error;
}

/// 用户可调强调色：统一从当前主题 ColorScheme 取 primary（亮暗自动适配）。
/// 取代历史上散落的 AppTheme.vermilion 硬编码。
extension AccentColor on BuildContext {
  Color get accent => Theme.of(this).colorScheme.primary;
}

/// 响应式间距 / 尺度
extension SpacingScale on BuildContext {
  ScreenSize get _screenSize =>
      AppTheme.screenSizeForWidth(MediaQuery.sizeOf(this).width);

  double get pagePadding => switch (_screenSize) {
        ScreenSize.small => 16,
        ScreenSize.medium => 20,
        ScreenSize.large => 24,
      };

  double get cardPaddingH => switch (_screenSize) {
        ScreenSize.small => 12,
        ScreenSize.medium => 14,
        ScreenSize.large => 16,
      };

  double get cardPaddingV => switch (_screenSize) {
        ScreenSize.small => 10,
        ScreenSize.medium => 11,
        ScreenSize.large => 12,
      };

  double get framePadding => cardPaddingH;

  double get gapTiny => 2;

  double get gapSmall => 4;

  double get gapMedium => switch (_screenSize) {
        ScreenSize.small => 6,
        ScreenSize.medium => 8,
        ScreenSize.large => 8,
      };

  double get gapLg => switch (_screenSize) {
        ScreenSize.small => 10,
        ScreenSize.medium => 14,
        ScreenSize.large => 16,
      };

  double get gapXl => switch (_screenSize) {
        ScreenSize.small => 16,
        ScreenSize.medium => 20,
        ScreenSize.large => 24,
      };

  double get gapXxl => switch (_screenSize) {
        ScreenSize.small => 24,
        ScreenSize.medium => 28,
        ScreenSize.large => 32,
      };
}
