import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Workshop typography scale for Anvil as defined in DESIGN_SYSTEM.md.
abstract class AppTypography {
  static TextStyle displayLarge(Brightness brightness) {
    return GoogleFonts.spaceGrotesk(
      fontSize: 32,
      fontWeight: FontWeight.w600,
      color: AppColors.text(brightness),
    );
  }

  static TextStyle displayMedium(Brightness brightness) {
    return GoogleFonts.spaceGrotesk(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: AppColors.text(brightness),
    );
  }

  static TextStyle titleMedium(Brightness brightness) {
    return GoogleFonts.spaceGrotesk(
      fontSize: 18,
      fontWeight: FontWeight.w500,
      color: AppColors.text(brightness),
    );
  }

  static TextStyle bodyLarge(Brightness brightness) {
    return GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: AppColors.text(brightness),
    );
  }

  static TextStyle bodyMedium(Brightness brightness) {
    return GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: AppColors.text(brightness),
    );
  }

  static TextStyle bodySmall(Brightness brightness) {
    return GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: AppColors.text(brightness),
    );
  }

  static TextStyle labelSmall(Brightness brightness) {
    return GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      color: AppColors.text(brightness),
    );
  }

  static TextStyle mono(Brightness brightness) {
    return GoogleFonts.ibmPlexMono(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: AppColors.text(brightness),
    );
  }
}
