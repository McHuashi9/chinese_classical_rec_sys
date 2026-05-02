import 'package:flutter/material.dart';

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

  // ─── 字号梯度 ─────────────────────────────────────────────────

  static const TextStyle bodyReading = TextStyle(
    fontSize: 18,
    fontFamily: fontBody,
    height: 1.8,
  );

  // ─── Light Theme ──────────────────────────────────────────────

  static final ThemeData lightTheme = ThemeData(
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
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 36, fontFamily: fontTitle, color: ink),
      headlineMedium: TextStyle(fontSize: 24, fontFamily: fontTitle, color: ink),
      titleLarge: TextStyle(fontSize: 20, fontFamily: fontTitle, color: ink),
      bodyLarge: TextStyle(fontSize: 16, fontFamily: fontBody, color: ink, height: 2.0),
      bodyMedium: TextStyle(fontSize: 14, fontFamily: fontUI, color: inkSecondary),
      labelSmall: TextStyle(fontSize: 12, fontFamily: fontUI, color: inkSecondary),
    ),
  );

  // ─── Dark Theme ───────────────────────────────────────────────

  static final ThemeData darkTheme = ThemeData(
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
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 36, fontFamily: fontTitle, color: darkInk),
      headlineMedium: TextStyle(fontSize: 24, fontFamily: fontTitle, color: darkInk),
      titleLarge: TextStyle(fontSize: 20, fontFamily: fontTitle, color: darkInk),
      bodyLarge: TextStyle(fontSize: 16, fontFamily: fontBody, color: darkInk, height: 2.0),
      bodyMedium: TextStyle(fontSize: 14, fontFamily: fontUI, color: darkInkSecondary),
      labelSmall: TextStyle(fontSize: 12, fontFamily: fontUI, color: darkInkSecondary),
    ),
  );
}
