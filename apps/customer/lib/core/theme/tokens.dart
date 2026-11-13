import 'package:flutter/material.dart';

class AppColors {
  static const petrol = Color(0xFF087F78);
  static const petrolDark = Color(0xFF06635E);
  static const petrolSoft = Color(0xFFE7F4F3);
  static const ink = Color(0xFF172334);
  static const inkSoft = Color(0xFF3E4C5E);
  static const muted = Color(0xFF6A7786);
  static const line = Color(0xFFE3E8EC);
  static const canvas = Color(0xFFF5F7F8);
  static const surface = Color(0xFFFFFFFF);
  static const amber = Color(0xFFC9842F);
  static const amberSoft = Color(0xFFFFF6EA);
  static const success = Color(0xFF1E7F4F);
  static const successSoft = Color(0xFFE8F6EE);
  static const danger = Color(0xFFC44747);
  static const dangerSoft = Color(0xFFF8EEEE);
}

class Space {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.canvas,
      fontFamily: 'Cairo',
      colorScheme: const ColorScheme.light(
        primary: AppColors.petrol,
        onPrimary: Colors.white,
        secondary: AppColors.amber,
        surface: AppColors.surface,
        error: AppColors.danger,
        onSurface: AppColors.ink,
      ),
    );
    return base.copyWith(
      splashFactory: InkRipple.splashFactory,
      dividerColor: AppColors.line,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      textTheme: base.textTheme.apply(
        fontFamily: 'Cairo',
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.petrolSoft,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.petrol : AppColors.muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? AppColors.petrol : AppColors.muted, size: 22);
        }),
      ),
    );
  }
}
