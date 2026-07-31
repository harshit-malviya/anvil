import 'package:flutter/material.dart';
import '../../tools/registry.dart';

/// Workshop color tokens for Anvil as defined in DESIGN_SYSTEM.md.
abstract class AppColors {
  // Light Mode Tokens
  static const Color ink = Color(0xFF1E2226);
  static const Color workshopGrey = Color(0xFFECEAE4);
  static const Color paperCard = Color(0xFFF7F6F2);

  // Dark Mode Tokens
  static const Color inkDark = Color(0xFFEDEBE6);
  static const Color forgeBlack = Color(0xFF15171A);
  static const Color steelCard = Color(0xFF1F2327);

  // Brand & Accent Tokens (Light)
  static const Color emberCopper = Color(0xFFB5502D);
  static const Color anvilBlue = Color(0xFF357ABD);
  static const Color sparkYellow = Color(0xFFE8B33D);
  static const Color rustRed = Color(0xFFA63A2E);
  static const Color pegGrey = Color(0xFFC7C4BC);

  // Brand & Accent Tokens (+8% luminance for Dark Mode)
  static const Color emberCopperDark = Color(0xFFC75D37);
  static const Color anvilBlueDark = Color(0xFF498ED1);

  // Convenient Theme Getters
  static Color background(Brightness brightness) =>
      brightness == Brightness.dark ? forgeBlack : workshopGrey;

  static Color cardBackground(Brightness brightness) =>
      brightness == Brightness.dark ? steelCard : paperCard;

  static Color text(Brightness brightness) =>
      brightness == Brightness.dark ? inkDark : ink;

  static Color primary(Brightness brightness) =>
      brightness == Brightness.dark ? emberCopperDark : emberCopper;

  static Color secondary(Brightness brightness) =>
      brightness == Brightness.dark ? anvilBlueDark : anvilBlue;

  static Color familyAccent(ToolCategory category, [Brightness brightness = Brightness.light]) =>
      category == ToolCategory.pdf
          ? (brightness == Brightness.dark ? emberCopperDark : emberCopper)
          : (brightness == Brightness.dark ? anvilBlueDark : anvilBlue);

  // Disabled State Tokens
  static Color disabledBackground(Brightness brightness) =>
      brightness == Brightness.dark
          ? const Color(0xFF26292E)
          : const Color(0xFFE2DFD7);

  static Color disabledText(Brightness brightness) =>
      brightness == Brightness.dark
          ? const Color(0xFF6C7075)
          : const Color(0xFF9E9B93);

  static Color disabledBorder(Brightness brightness) =>
      brightness == Brightness.dark
          ? const Color(0xFF32363C)
          : const Color(0xFFD0CDC5);
}

