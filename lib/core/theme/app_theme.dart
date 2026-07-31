import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// ThemeData builder for Light and Dark workshop modes.
abstract class AppTheme {
  static const double borderRadius = 6.0;

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.workshopGrey,
      colorScheme: const ColorScheme.light(
        primary: AppColors.emberCopper,
        secondary: AppColors.anvilBlue,
        surface: AppColors.paperCard,
        error: AppColors.rustRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.ink,
        onError: Colors.white,
      ),
      focusColor: AppColors.emberCopper,
      dividerColor: AppColors.pegGrey,
      disabledColor: AppColors.disabledText(Brightness.light),
      cardTheme: CardThemeData(
        color: AppColors.paperCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: const BorderSide(color: AppColors.pegGrey, width: 1.0),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.emberCopper,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.disabledBackground(Brightness.light),
          disabledForegroundColor: AppColors.disabledText(Brightness.light),
          minimumSize: const Size(88, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          elevation: 0,
          textStyle: AppTypography.bodyMedium(Brightness.light).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.emberCopper,
          disabledForegroundColor: AppColors.disabledText(Brightness.light),
          side: const BorderSide(color: AppColors.emberCopper, width: 1.5),
          minimumSize: const Size(88, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          textStyle: AppTypography.bodyMedium(Brightness.light).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          disabledForegroundColor: AppColors.disabledText(Brightness.light),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          disabledForegroundColor: AppColors.disabledText(Brightness.light),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.emberCopper;
            }
            if (states.contains(WidgetState.disabled)) {
              return AppColors.disabledBackground(Brightness.light);
            }
            return AppColors.paperCard;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            if (states.contains(WidgetState.disabled)) {
              return AppColors.disabledText(Brightness.light);
            }
            return AppColors.ink;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: AppColors.disabledBorder(Brightness.light));
            }
            return const BorderSide(color: AppColors.pegGrey);
          }),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.paperCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: AppColors.pegGrey, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: AppColors.pegGrey, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: AppColors.emberCopper, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: AppColors.rustRed, width: 1.5),
        ),
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.forgeBlack,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.emberCopperDark,
        secondary: AppColors.anvilBlueDark,
        surface: AppColors.steelCard,
        error: AppColors.rustRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.inkDark,
        onError: Colors.white,
      ),
      focusColor: AppColors.emberCopperDark,
      dividerColor: AppColors.pegGrey.withValues(alpha: 0.3),
      disabledColor: AppColors.disabledText(Brightness.dark),
      cardTheme: CardThemeData(
        color: AppColors.steelCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(
            color: AppColors.pegGrey.withValues(alpha: 0.2),
            width: 1.0,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.emberCopperDark,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.disabledBackground(Brightness.dark),
          disabledForegroundColor: AppColors.disabledText(Brightness.dark),
          minimumSize: const Size(88, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          elevation: 0,
          textStyle: AppTypography.bodyMedium(Brightness.dark).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.emberCopperDark,
          disabledForegroundColor: AppColors.disabledText(Brightness.dark),
          side: const BorderSide(color: AppColors.emberCopperDark, width: 1.5),
          minimumSize: const Size(88, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          textStyle: AppTypography.bodyMedium(Brightness.dark).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          disabledForegroundColor: AppColors.disabledText(Brightness.dark),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          disabledForegroundColor: AppColors.disabledText(Brightness.dark),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.emberCopperDark;
            }
            if (states.contains(WidgetState.disabled)) {
              return AppColors.disabledBackground(Brightness.dark);
            }
            return AppColors.steelCard;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            if (states.contains(WidgetState.disabled)) {
              return AppColors.disabledText(Brightness.dark);
            }
            return AppColors.inkDark;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: AppColors.disabledBorder(Brightness.dark));
            }
            return BorderSide(color: AppColors.pegGrey.withValues(alpha: 0.3));
          }),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.steelCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: BorderSide(
            color: AppColors.pegGrey.withValues(alpha: 0.3),
            width: 1.0,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: BorderSide(
            color: AppColors.pegGrey.withValues(alpha: 0.3),
            width: 1.0,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: AppColors.emberCopperDark, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          borderSide: const BorderSide(color: AppColors.rustRed, width: 1.5),
        ),
      ),
    );
  }
}
