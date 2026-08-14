import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFFFFFFFF);
  static const canvas = Color(0xFFF7F8FA);
  static const surface = Color(0xFFF7F8FA);
  static const foreground = Color(0xFF111111);
  static const muted = Color(0xFF6B7280);
  static const border = Color(0xFFD9DEE7);
  static const accent = Color(0xFF1677FF);
  static const accentHover = Color(0xFF0958D9);
  static const accentSoft = Color(0xFFEDF4FF);
  static const danger = Color(0xFFD4380D);
  static const success = Color(0xFF178553);
}

ThemeData buildTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.light,
    surface: AppColors.background,
  ).copyWith(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    onSurface: AppColors.foreground,
    error: AppColors.danger,
    outline: AppColors.border,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Inter',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.9,
        color: AppColors.foreground,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        height: 1.2,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: AppColors.foreground,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w700,
        color: AppColors.foreground,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.foreground,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        height: 1.6,
        color: AppColors.foreground,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.55,
        color: AppColors.foreground,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.45,
        color: AppColors.muted,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.accent),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        foregroundColor: AppColors.foreground,
      ),
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.foreground,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.background,
      selectedColor: AppColors.foreground,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: const TextStyle(color: AppColors.foreground),
      secondaryLabelStyle: const TextStyle(color: AppColors.background),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    dividerColor: AppColors.border,
  );
}
