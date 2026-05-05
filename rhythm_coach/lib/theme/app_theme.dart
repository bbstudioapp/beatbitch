import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF161616);
  static const Color accent = Color(0xFFFFA726);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color textMuted = Color(0xFF707070);

  static ThemeData build() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: surface,
      ),
      scaffoldBackgroundColor: background,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: accent,
        thumbColor: accent,
        inactiveTrackColor: Color(0xFF333333),
      ),
    );
  }
}
