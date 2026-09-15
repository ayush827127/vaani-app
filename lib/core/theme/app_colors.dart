import 'package:flutter/material.dart';

class AppColors {
  // Primary
  static const Color primary = Color(0xFF6B21A8);
  static const Color primaryLight = Color(0xFF7C3AED);
  static const Color primaryDark = Color(0xFF4C1D95);

  // Dark surfaces
  static const Color surfaceDark = Color(0xFF1E1B4B);
  static const Color surfaceVariantDark = Color(0xFF2D2B5E);
  static const Color onSurfaceDark = Color(0xFFFFFFFF);
  static const Color onSurfaceVariantDark = Color(0xFFC4B5FD);

  // Light surfaces
  static const Color backgroundLight = Color(0xFFF8F7FF);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color onBackgroundLight = Color(0xFF1E1B4B);
  static const Color onSurfaceLight = Color(0xFF374151);
  static const Color borderLight = Color(0xFFE5E7EB);

  // Semantic colors
  static const Color success = Color(0xFF16A34A);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color error = Color(0xFFDC2626);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color warning = Color(0xFFEA580C);
  static const Color warningLight = Color(0xFFFED7AA);
  static const Color info = Color(0xFF2563EB);
  static const Color infoLight = Color(0xFFDBEAFE);

  // Chart colors
  static const Color chartLine = Color(0xFF7C3AED);
  static const Color chartFill = Color(0x337C3AED);
  static const Color chartGreen = Color(0xFF16A34A);
  static const Color chartRed = Color(0xFFDC2626);
  static const Color chartOrange = Color(0xFFEA580C);

  // Gradient
  static const LinearGradient splashGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1E1B4B), Color(0xFF4C1D95)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2D2B5E), Color(0xFF1E1B4B)],
  );

  // ── Light Theme palette (spec: Razorpay/Vyapar/Material3-style, soft & premium) ──
  static const Color scaffoldLight = Color(0xFFF6F7FB);
  static const Color cardBorderLight = Color(0xFFECECF3);
  static const Color textPrimaryLight = Color(0xFF111827);
  static const Color textSecondaryLight = Color(0xFF6B7280);
  static const Color textHintLight = Color(0xFF9CA3AF);
  static const Color textDisabledLight = Color(0xFFD1D5DB);

  static const Color primaryLightTheme = Color(0xFF7C3AED);
  static const Color primaryDarkLightTheme = Color(0xFF6D28D9);

  static const Color successLightTheme = Color(0xFF22C55E);
  static const Color warningLightTheme = Color(0xFFF59E0B);
  static const Color dangerLightTheme = Color(0xFFEF4444);
  static const Color infoLightTheme = Color(0xFF3B82F6);

  static const LinearGradient heroGradientLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
  );

  static const LinearGradient heroGradientDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4C1D95), Color(0xFF6B21A8)],
  );
}

/// Semantic, theme-aware tokens for surfaces/text/status that screens read via
/// `context.colors` instead of hardcoding dark-only [AppColors] constants.
/// Dark values are identical to the literals the app already used, so the
/// existing Dark Theme renders pixel-for-pixel the same as before.
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color surface;
  final Color surfaceBorder;
  final Color inputBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textHint;
  final Color textDisabled;
  final Color divider;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final LinearGradient heroGradient;

  const AppSemanticColors({
    required this.surface,
    required this.surfaceBorder,
    required this.inputBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textHint,
    required this.textDisabled,
    required this.divider,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.heroGradient,
  });

  static const dark = AppSemanticColors(
    surface: AppColors.surfaceVariantDark,
    surfaceBorder: Color(0xFF3D3B6E),
    inputBorder: Color(0xFF3D3B6E),
    textPrimary: Colors.white,
    textSecondary: Colors.white70,
    textHint: Colors.white54,
    textDisabled: Colors.white38,
    divider: Color(0xFF3D3B6E),
    success: AppColors.success,
    warning: AppColors.warning,
    danger: AppColors.error,
    info: AppColors.info,
    heroGradient: AppColors.heroGradientDark,
  );

  static const light = AppSemanticColors(
    surface: Colors.white,
    surfaceBorder: AppColors.cardBorderLight,
    inputBorder: AppColors.borderLight,
    textPrimary: AppColors.textPrimaryLight,
    textSecondary: AppColors.textSecondaryLight,
    textHint: AppColors.textHintLight,
    textDisabled: AppColors.textDisabledLight,
    divider: AppColors.borderLight,
    success: AppColors.successLightTheme,
    warning: AppColors.warningLightTheme,
    danger: AppColors.dangerLightTheme,
    info: AppColors.infoLightTheme,
    heroGradient: AppColors.heroGradientLight,
  );

  @override
  AppSemanticColors copyWith({
    Color? surface,
    Color? surfaceBorder,
    Color? inputBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? textHint,
    Color? textDisabled,
    Color? divider,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    LinearGradient? heroGradient,
  }) {
    return AppSemanticColors(
      surface: surface ?? this.surface,
      surfaceBorder: surfaceBorder ?? this.surfaceBorder,
      inputBorder: inputBorder ?? this.inputBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textHint: textHint ?? this.textHint,
      textDisabled: textDisabled ?? this.textDisabled,
      divider: divider ?? this.divider,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      heroGradient: heroGradient ?? this.heroGradient,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return t < 0.5 ? this : other;
  }
}

extension AppSemanticColorsX on BuildContext {
  AppSemanticColors get colors => Theme.of(this).extension<AppSemanticColors>() ?? AppSemanticColors.dark;
}
