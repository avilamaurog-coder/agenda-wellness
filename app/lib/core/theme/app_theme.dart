import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Tema Material 3 con tipografía serif para títulos (sensación spa)
/// y sans geométrica para lectura de datos.
abstract final class AppTheme {
  static ThemeData light() => _build(
        ColorScheme.fromSeed(
          seedColor: AppColors.sage,
          brightness: Brightness.light,
          surface: AppColors.sand,
          secondary: AppColors.terracotta,
        ),
      );

  static ThemeData dark() => _build(
        ColorScheme.fromSeed(
          seedColor: AppColors.sage,
          brightness: Brightness.dark,
          surface: AppColors.night,
          secondary: AppColors.terracotta,
        ),
      );

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final body = GoogleFonts.dmSansTextTheme(base.textTheme);
    final display = GoogleFonts.frauncesTextTheme(base.textTheme);

    final text = body.copyWith(
      displayLarge: display.displayLarge,
      displayMedium: display.displayMedium,
      displaySmall: display.displaySmall,
      headlineLarge: display.headlineLarge?.copyWith(fontWeight: FontWeight.w600),
      headlineMedium: display.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
      headlineSmall: display.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
    );

    final radius = BorderRadius.circular(16);

    return base.copyWith(
      textTheme: text.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: radius),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
