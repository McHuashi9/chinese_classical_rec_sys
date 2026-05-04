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
  static const Color vermilion = Color(0xFFB33A3A);
  static const Color vermilionHover = Color(0xFF932E2E);
  static const Color stoneGreen = Color(0xFF5B7B4A);
  static const Color border = Color(0xFFC2B28F);
  static const Color borderLight = Color(0xFFD4C9A8);
  static const Color overlay = Color(0xCC1C1812);

  static const Color darkPaper = Color(0xFF1C1812);
  static const Color darkCard = Color(0xFF2A251D);
  static const Color darkInk = Color(0xFFD4C9A8);
  static const Color darkInkSecondary = Color(0xFF9A9278);
  static const Color darkVermilion = Color(0xFFC75B5B);

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

  static TextStyle bodyReadingSize(ScreenSize size) => TextStyle(
        fontSize: switch (size) {
          ScreenSize.small => 15,
          ScreenSize.medium => 16,
          ScreenSize.large => 18,
        },
        fontFamily: fontBody,
        height: 1.8,
      );

  static const TextStyle bodyReading = TextStyle(
    fontSize: 18,
    fontFamily: fontBody,
    height: 1.8,
  );

  // ─── Light Theme ──────────────────────────────────────────────

  static ThemeData lightTheme(ScreenSize size) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: vermilion,
          brightness: Brightness.light,
          surface: paper,
        ),
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
              fontSize: _headlineLarge(size),
              fontFamily: fontTitle,
              color: ink),
          headlineMedium: TextStyle(
              fontSize: _headlineMedium(size),
              fontFamily: fontTitle,
              color: ink),
          titleLarge: TextStyle(
              fontSize: _titleLarge(size),
              fontFamily: fontTitle,
              color: ink),
          bodyLarge: TextStyle(
              fontSize: _bodyLarge(size),
              fontFamily: fontBody,
              color: ink,
              height: 2.0),
          bodyMedium: const TextStyle(
              fontSize: 14,
              fontFamily: fontUI,
              color: inkSecondary),
          labelSmall: const TextStyle(
              fontSize: 12,
              fontFamily: fontUI,
              color: inkSecondary),
        ),
      );

  // ─── Dark Theme ───────────────────────────────────────────────

  static ThemeData darkTheme(ScreenSize size) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: darkVermilion,
          brightness: Brightness.dark,
          surface: darkPaper,
        ),
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
              fontSize: _headlineLarge(size),
              fontFamily: fontTitle,
              color: darkInk),
          headlineMedium: TextStyle(
              fontSize: _headlineMedium(size),
              fontFamily: fontTitle,
              color: darkInk),
          titleLarge: TextStyle(
              fontSize: _titleLarge(size),
              fontFamily: fontTitle,
              color: darkInk),
          bodyLarge: TextStyle(
              fontSize: _bodyLarge(size),
              fontFamily: fontBody,
              color: darkInk,
              height: 2.0),
          bodyMedium: const TextStyle(
              fontSize: 14,
              fontFamily: fontUI,
              color: darkInkSecondary),
          labelSmall: const TextStyle(
              fontSize: 12,
              fontFamily: fontUI,
              color: darkInkSecondary),
        ),
      );
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

  double get gapHuge => switch (_screenSize) {
        ScreenSize.small => 10,
        ScreenSize.medium => 14,
        ScreenSize.large => 16,
      };

  double get gapXHuge => switch (_screenSize) {
        ScreenSize.small => 16,
        ScreenSize.medium => 20,
        ScreenSize.large => 24,
      };

  double get gapXXHuge => switch (_screenSize) {
        ScreenSize.small => 24,
        ScreenSize.medium => 28,
        ScreenSize.large => 32,
      };
}
