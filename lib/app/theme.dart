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

  // Modern light look: soft grey page, white cards and tiles, light app bar.
  const page = Color(0xFFF1F5F9);
  final soft = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: page,
    appBarTheme: const AppBarTheme(
      backgroundColor: page,
      foregroundColor: AppColors.slate900,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.slate900,
        fontSize: 21,
        fontWeight: FontWeight.w800,
      ),
    ),
    // Lists sit on the grey page as white rows.
    listTileTheme: ListTileThemeData(
      tileColor: AppColors.surface,
      iconColor: AppColors.slate600,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      shape: const RoundedRectangleBorder(),
      selectedTileColor: AppColors.amber100,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.amber100,
      side: const BorderSide(color: AppColors.border),
      shape: soft,
      labelStyle: const TextStyle(
        color: AppColors.slate900,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: AppColors.surface,
        selectedBackgroundColor: AppColors.amber500,
        selectedForegroundColor: AppColors.slate900,
        foregroundColor: AppColors.slate900,
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: AppColors.surface),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      showDragHandle: true,
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
    // Borderless filled fields; a coloured outline only while typing.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.blue700, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.amber100,
      height: 68,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
