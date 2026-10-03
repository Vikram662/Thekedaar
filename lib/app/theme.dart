import 'package:flutter/material.dart';

/// Design tokens from PRD E3. Bright fills are never used for text on white
/// (PRD I-D1); amber always carries dark text (I-D2).
abstract final class AppColors {
  static const slate900 = Color(0xFF0F172A);
  static const slate600 = Color(0xFF475569);
  static const amber500 = Color(0xFFF59E0B);
  static const amber100 = Color(0xFFFEF3C7);
  static const blue600 = Color(0xFF0284C7);
  static const blue700 = Color(0xFF0369A1);

  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF8FAFC);
  static const border = Color(0xFFE2E8F0);

  static const successFill = Color(0xFF059669);
  static const successText = Color(0xFF047857);
  static const warningFill = Color(0xFFD97706);
  static const warningText = Color(0xFFB45309);
  static const dangerFill = Color(0xFFE11D48);
  static const dangerText = Color(0xFFBE123C);
  static const dangerSurface = Color(0xFFFFF1F2);
}

abstract final class AppSizes {
  static const double tapMin = 48;
  static const double tapPrimary = 56;
  static const double gap = 8;
  static const double radius = 12;
  static const double gutter = 16;
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.blue700).copyWith(
    primary: AppColors.blue700,
    onPrimary: Colors.white,
    secondary: AppColors.amber500,
    onSecondary: AppColors.slate900,
    error: AppColors.dangerText,
    onError: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.slate900,
    onSurfaceVariant: AppColors.slate600,
    outline: AppColors.slate600,
    outlineVariant: AppColors.border,
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppSizes.radius),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.surface2,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.slate900,
      foregroundColor: Colors.white,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.amber500,
        foregroundColor: AppColors.slate900,
        minimumSize: const Size(64, AppSizes.tapPrimary),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, AppSizes.tapMin),
        shape: shape,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.amber500,
      foregroundColor: AppColors.slate900,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSizes.radius),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.amber100,
    ),
  );
}
