import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  // ── Dark Theme ────────────────────────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          primaryContainer: AppColors.primaryDark,
          onPrimaryContainer: Colors.white,
          secondary: AppColors.primaryLight,
          onSecondary: Colors.white,
          surface: AppColors.surfaceDark,
          onSurface: Colors.white,
          surfaceContainerLowest: Color(0xFF1A1740),
          surfaceContainer: AppColors.surfaceVariantDark,
          surfaceContainerHighest: Color(0xFF3D3B6E),
          outline: Color(0xFF6B6A8F),
          outlineVariant: Color(0xFF3D3B6E),
          error: AppColors.error,
          onError: Colors.white,
        ),
        extensions: const [AppSemanticColors.dark],
        scaffoldBackgroundColor: AppColors.surfaceDark,
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surfaceDark,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: AppColors.surfaceVariantDark,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: AppColors.surfaceVariantDark,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF3D3B6E)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryLight,
            minimumSize: const Size(double.infinity, 52),
            side: const BorderSide(color: AppColors.primaryLight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceVariantDark,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF3D3B6E)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.error),
          ),
          labelStyle: const TextStyle(color: AppColors.onSurfaceVariantDark),
          hintStyle: const TextStyle(color: Color(0xFF6B6A8F)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.surfaceVariantDark,
          selectedItemColor: AppColors.primaryLight,
          unselectedItemColor: Color(0xFF6B6A8F),
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.surfaceVariantDark,
          selectedColor: AppColors.primary,
          labelStyle: const TextStyle(color: AppColors.onSurfaceVariantDark),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF3D3B6E)),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF3D3B6E),
          thickness: 1,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surfaceVariantDark,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titleTextStyle: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Poppins'),
          contentTextStyle: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.surfaceVariantDark,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppColors.primaryLight : Colors.grey),
          trackColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? AppColors.primaryLight.withValues(alpha: 0.4)
                  : Colors.grey.withValues(alpha: 0.3)),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: AppColors.primaryLight,
          textColor: Colors.white,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontFamily: 'Poppins', fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
          displayMedium: TextStyle(fontFamily: 'Poppins', fontSize: 24, fontWeight: FontWeight.w600, color: Colors.white),
          headlineLarge: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
          headlineMedium: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white),
          titleLarge: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
          titleMedium: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.onSurfaceVariantDark),
          bodyLarge: TextStyle(fontFamily: 'Inter', fontSize: 16, color: Colors.white),
          bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.onSurfaceVariantDark),
          bodySmall: TextStyle(fontFamily: 'Inter', fontSize: 12, color: Color(0xFF6B6A8F)),
          labelLarge: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
        ),
      );

  // ── Light Theme ───────────────────────────────────────────────────────────────
  // Independently designed — not an inversion of Dark. Soft neutral background,
  // elevated white cards with hairline borders, solid/gradient purple accents.
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primaryLightTheme,
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFEDE4FF),
          onPrimaryContainer: AppColors.primaryDarkLightTheme,
          secondary: AppColors.primaryDarkLightTheme,
          onSecondary: Colors.white,
          surface: Colors.white,
          onSurface: AppColors.textPrimaryLight,
          surfaceContainerLowest: AppColors.scaffoldLight,
          surfaceContainer: Color(0xFFF6F7FB),
          surfaceContainerHighest: Color(0xFFEDE4FF),
          outline: AppColors.textHintLight,
          outlineVariant: AppColors.cardBorderLight,
          error: AppColors.dangerLightTheme,
          onError: Colors.white,
        ),
        extensions: const [AppSemanticColors.light],
        scaffoldBackgroundColor: AppColors.scaffoldLight,
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.scaffoldLight,
          foregroundColor: AppColors.textPrimaryLight,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
          shadowColor: Color(0x14000000),
          titleTextStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryLight,
          ),
          iconTheme: IconThemeData(color: AppColors.textPrimaryLight),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.black.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.cardBorderLight),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryLightTheme,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.textDisabledLight,
            disabledForegroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimaryLight,
            minimumSize: const Size(double.infinity, 52),
            side: const BorderSide(color: AppColors.borderLight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: AppColors.primaryLightTheme),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primaryLightTheme,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.borderLight),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.borderLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primaryLightTheme, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.dangerLightTheme),
          ),
          labelStyle: const TextStyle(color: AppColors.textSecondaryLight),
          hintStyle: const TextStyle(color: AppColors.textHintLight),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.primaryLightTheme,
          unselectedItemColor: AppColors.textHintLight,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white,
          selectedColor: AppColors.primaryLightTheme,
          labelStyle: const TextStyle(color: AppColors.textPrimaryLight),
          secondaryLabelStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.borderLight),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.borderLight,
          thickness: 1,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titleTextStyle: const TextStyle(
              color: AppColors.textPrimaryLight, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Poppins'),
          contentTextStyle: const TextStyle(color: AppColors.textSecondaryLight, fontSize: 14),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.textPrimaryLight,
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? AppColors.primaryLightTheme : Colors.white),
          trackColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? AppColors.primaryLightTheme.withValues(alpha: 0.4)
                  : const Color(0xFFE5E7EB)),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: AppColors.primaryLightTheme,
          textColor: AppColors.textPrimaryLight,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontFamily: 'Poppins', fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textPrimaryLight),
          displayMedium: TextStyle(fontFamily: 'Poppins', fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.textPrimaryLight),
          headlineLarge: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimaryLight),
          headlineMedium: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.textPrimaryLight),
          titleLarge: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimaryLight),
          titleMedium: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondaryLight),
          bodyLarge: TextStyle(fontFamily: 'Inter', fontSize: 16, color: AppColors.textPrimaryLight),
          bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.textSecondaryLight),
          bodySmall: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textHintLight),
          labelLarge: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimaryLight),
        ),
      );
}
