import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens transcribed from
/// stitch_jakroute_ui_ux_design_system/jakroute/DESIGN.md
class AppColors {
  static const surface = Color(0xFFF7F9FB);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF2F4F6);
  static const surfaceContainer = Color(0xFFECEEF0);
  static const surfaceContainerHigh = Color(0xFFE6E8EA);
  static const onSurface = Color(0xFF191C1E);
  static const onSurfaceVariant = Color(0xFF43474E);
  static const outline = Color(0xFF74777F);
  static const outlineVariant = Color(0xFFC4C6CF);

  static const primary = Color(0xFF002045);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFF1A365D);
  static const onPrimaryContainer = Color(0xFF86A0CD);

  static const secondary = Color(0xFF0058BC);
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFF0070EB);

  static const tertiary = Color(0xFF301C00);
  static const tertiaryContainer = Color(0xFF4D2F00);
  static const tertiaryFixedDim = Color(0xFFFFB95A);

  static const error = Color(0xFFBA1A1A);
  static const errorContainer = Color(0xFFFFDAD6);

  // Functional accents (DESIGN.md > Colors)
  static const warning = Color(0xFFFFB347);
  static const success = Color(0xFF28A745);
  static const danger = Color(0xFFDC3545);
  static const hairline = Color(0xFFE2E8F0);
  static const accentLight = Color(0xFFEBF3FF);
  static const slate = Color(0xFF475569);
  static const slateLight = Color(0xFF94A3B8);
}

/// 4px baseline grid.
class Space {
  static const base = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const gutter = 16.0;
}

class Radii {
  static const sm = 4.0;
  static const std = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const full = 9999.0;
}

ThemeData buildAppTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
  final text = GoogleFonts.interTextTheme(base.textTheme)
      .copyWith(
        displayLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          height: 40 / 32,
          letterSpacing: -0.64,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          height: 32 / 24,
          letterSpacing: -0.24,
        ),
        headlineSmall: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 28 / 20,
        ),
        bodyLarge: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w400, height: 26 / 18),
        bodyMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, height: 24 / 16),
        labelMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 20 / 14,
          letterSpacing: 0.14,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 16 / 12,
          letterSpacing: 0.24,
        ),
      )
      .apply(bodyColor: AppColors.onSurface, displayColor: AppColors.onSurface);

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.surface,
    textTheme: text,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: AppColors.secondaryContainer,
      tertiary: AppColors.tertiary,
      tertiaryContainer: AppColors.tertiaryContainer,
      error: AppColors.error,
      errorContainer: AppColors.errorContainer,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      onSurfaceVariant: AppColors.onSurfaceVariant,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surfaceContainerLowest,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surfaceContainerLowest,
      indicatorColor: AppColors.accentLight,
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => text.labelSmall!.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected) ? AppColors.secondary : AppColors.onSurfaceVariant)),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? AppColors.secondary : AppColors.onSurfaceVariant)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.md), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md), borderSide: const BorderSide(color: AppColors.secondary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
      hintStyle: text.bodyMedium?.copyWith(color: AppColors.outline),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.hairline, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
        textStyle: text.labelMedium?.copyWith(fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.std)),
        textStyle: text.labelMedium?.copyWith(fontSize: 16),
      ),
    ),
  );
}

/// DESIGN.md > Elevation. Level 1 surfaces and Level 2/3 floating anchors.
const kSurfaceShadow = BoxShadow(color: Color(0x14002045), blurRadius: 8, offset: Offset(0, 2));
const kRaisedShadow = BoxShadow(color: Color(0x1F002045), blurRadius: 24, offset: Offset(0, 8));
const kAccentShadow = BoxShadow(color: Color(0x400058BC), blurRadius: 32, offset: Offset(0, 12));
