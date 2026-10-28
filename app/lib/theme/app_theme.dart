import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';

/// Shared radii, spacing and shadow tokens so every screen feels like one system.
class AppRadius {
  AppRadius._();
  static const double card = 16;
  static const double control = 12;
  static const double tile = 14;
  static const double pill = 999;
}

class AppShadows {
  AppShadows._();
  static List<BoxShadow> card = const [
    BoxShadow(color: Color(0x0F16233B), blurRadius: 18, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A0F1B2D), blurRadius: 3, offset: Offset(0, 1)),
  ];
  static List<BoxShadow> raised = const [
    BoxShadow(color: Color(0x1A16233B), blurRadius: 24, offset: Offset(0, 12)),
  ];
}

class AppTheme {
  AppTheme._();

  static const String fontFamily = 'Inter';

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: fontFamily,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.accent,
      onSecondary: AppColors.onAccent,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.danger,
      brightness: Brightness.light,
    );

    final textTheme = _textTheme(base.textTheme);

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: AppColors.ink,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: const TextStyle(color: AppColors.faint, fontWeight: FontWeight.w400),
        border: _inputBorder(AppColors.line),
        enabledBorder: _inputBorder(AppColors.line),
        focusedBorder: _inputBorder(AppColors.accent, width: 1.6),
        errorBorder: _inputBorder(AppColors.danger),
        focusedErrorBorder: _inputBorder(AppColors.danger, width: 1.6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.track,
        thumbColor: AppColors.accent,
        overlayColor: AppColors.accent.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.track,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color c, {double width = 1.2}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
      borderSide: BorderSide(color: c, width: width),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    TextStyle s(double size, FontWeight w, {double? h, double? ls, Color? c}) => TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: w,
          height: h,
          letterSpacing: ls,
          color: c ?? AppColors.ink,
        );
    return base.copyWith(
      displaySmall: s(30, FontWeight.w800, h: 1.1, ls: -0.5),
      headlineMedium: s(24, FontWeight.w800, h: 1.15, ls: -0.4),
      headlineSmall: s(20, FontWeight.w700, h: 1.2, ls: -0.2),
      titleLarge: s(17, FontWeight.w700, h: 1.25),
      titleMedium: s(15, FontWeight.w600, h: 1.3),
      titleSmall: s(13, FontWeight.w600, h: 1.3),
      bodyLarge: s(15, FontWeight.w400, h: 1.45),
      bodyMedium: s(13.5, FontWeight.w400, h: 1.45, c: AppColors.muted),
      bodySmall: s(12, FontWeight.w400, h: 1.4, c: AppColors.muted),
      labelLarge: s(15, FontWeight.w600, h: 1.2),
      labelMedium: s(12, FontWeight.w600, h: 1.2, c: AppColors.muted),
      labelSmall: s(11, FontWeight.w600, ls: 0.6, c: AppColors.muted),
    );
  }
}
