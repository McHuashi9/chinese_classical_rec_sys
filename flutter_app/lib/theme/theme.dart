import 'package:flutter/material.dart';

/// 设计系统 Token → Flutter ThemeData
/// 颜色/字体/间距复用 design-spec.md
class AppTheme {
  AppTheme._();

  // ─── 颜色 Token (design-spec.md) ──────────────────────────────

  static const Color inkBlack = Color(0xFF2C2C2C);
  static const Color parchment = Color(0xFFF5F0E8);
  static const Color silkWhite = Color(0xFFFAFAF5);
  static const Color cinnabar = Color(0xFFC43A31);
  static const Color celadon = Color(0xFF7BA38A);
  static const Color warmGray = Color(0xFF8C8C7C);
  static const Color accentGold = Color(0xFFD4A843);

  static const String serifFont = 'SourceHanSerifSC';
  static const String sansFont = 'HarmonyOSSansSC';

  // ─── Light Theme ──────────────────────────────────────────────

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: cinnabar,
      brightness: Brightness.light,
      surface: parchment,
    ),
    scaffoldBackgroundColor: parchment,
    appBarTheme: const AppBarTheme(
      backgroundColor: parchment,
      foregroundColor: inkBlack,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 36, fontFamily: serifFont, color: inkBlack),
      headlineMedium: TextStyle(fontSize: 24, fontFamily: serifFont, color: inkBlack),
      titleLarge: TextStyle(fontSize: 20, fontFamily: sansFont, color: inkBlack),
      bodyLarge: TextStyle(fontSize: 16, fontFamily: serifFont, color: inkBlack, height: 2.0),
      bodyMedium: TextStyle(fontSize: 14, fontFamily: sansFont, color: warmGray),
      labelSmall: TextStyle(fontSize: 12, fontFamily: sansFont, color: warmGray),
    ),
  );

  // ─── Dark Theme ───────────────────────────────────────────────

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: cinnabar,
      brightness: Brightness.dark,
      surface: const Color(0xFF1E1E1E),
    ),
    scaffoldBackgroundColor: const Color(0xFF1E1E1E),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
          fontSize: 36, fontFamily: serifFont,
          color: Color(0xFFE0D8C8)),
      headlineMedium: TextStyle(
          fontSize: 24, fontFamily: serifFont,
          color: Color(0xFFE0D8C8)),
      titleLarge: TextStyle(
          fontSize: 20, fontFamily: sansFont,
          color: Color(0xFFE0D8C8)),
      bodyLarge: TextStyle(
          fontSize: 16, fontFamily: serifFont,
          color: Color(0xFFD0C8B8), height: 2.0),
      bodyMedium: TextStyle(
          fontSize: 14, fontFamily: sansFont,
          color: Color(0xFF909080)),
      labelSmall: TextStyle(
          fontSize: 12, fontFamily: sansFont,
          color: Color(0xFF909080)),
    ),
  );
}
