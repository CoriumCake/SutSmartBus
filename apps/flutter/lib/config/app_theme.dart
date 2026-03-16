import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Custom color extensions for app-specific colors not in ThemeData
class AppColors extends ThemeExtension<AppColors> {
  final Color surface;
  final Color textMuted;
  final Color primaryLight;
  final Color tabBarBorder;

  AppColors({
    required this.surface,
    required this.textMuted,
    required this.primaryLight,
    required this.tabBarBorder,
  });

  @override
  AppColors copyWith({
    Color? surface,
    Color? textMuted,
    Color? primaryLight,
    Color? tabBarBorder,
  }) {
    return AppColors(
      surface: surface ?? this.surface,
      textMuted: textMuted ?? this.textMuted,
      primaryLight: primaryLight ?? this.primaryLight,
      tabBarBorder: tabBarBorder ?? this.tabBarBorder,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      surface: Color.lerp(surface, other.surface, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      tabBarBorder: Color.lerp(tabBarBorder, other.tabBarBorder, t)!,
    );
  }
}

/// Light theme colors
const _lightPrimary = Color(0xFFF57C00);   // SUT Orange
const _lightOnPrimary = Colors.white;

/// Dark theme colors
const _darkPrimary = Color(0xFFFFB74D);    // Lighter orange for dark mode

/// Build the light ThemeData
final ThemeData lightThemeData = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: const ColorScheme.light(
    primary: _lightPrimary,
    onPrimary: _lightOnPrimary,
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF333333),
    secondary: _lightPrimary,
    outline: Color(0xFFEEEEEE),
  ),
  scaffoldBackgroundColor: const Color(0xFFFFFFFF),
  cardColor: const Color(0xFFFFFFFF),
  textTheme: GoogleFonts.interTextTheme().apply(
    bodyColor: const Color(0xFF333333),
    displayColor: const Color(0xFF333333),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: Color(0xFF333333),
    elevation: 0,
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: Colors.white,
    selectedItemColor: _lightPrimary,
    unselectedItemColor: Color(0xFF999999),
  ),
  dividerColor: const Color(0xFFEEEEEE),
  extensions: [
    AppColors(
      surface: const Color(0xFFF5F5F5),
      textMuted: const Color(0xFF999999),
      primaryLight: const Color(0xFFFFF3E0),
      tabBarBorder: const Color(0xFFEEEEEE),
    ),
  ],
);

/// Build the dark ThemeData
final ThemeData darkThemeData = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: _darkPrimary,
    onPrimary: Colors.black,
    surface: Color(0xFF121212),
    onSurface: Color(0xFFFFFFFF),
    secondary: _darkPrimary,
    outline: Color(0xFF333333),
  ),
  scaffoldBackgroundColor: const Color(0xFF121212),
  cardColor: const Color(0xFF252525),
  textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
    bodyColor: Colors.white,
    displayColor: Colors.white,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF1E1E1E),
    foregroundColor: Colors.white,
    elevation: 0,
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: Color(0xFF1E1E1E),
    selectedItemColor: _darkPrimary,
    unselectedItemColor: Color(0xFF707070),
  ),
  dividerColor: const Color(0xFF333333),
  extensions: [
    AppColors(
      surface: const Color(0xFF1E1E1E),
      textMuted: const Color(0xFF707070),
      primaryLight: const Color(0xFF3D2A1A),
      tabBarBorder: const Color(0xFF333333),
    ),
  ],
);
