import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A modern, highly structured theme for SUT Smart Bus.
/// Focuses on readability, high contrast, and a professional look.
class AppTheme {
  // Brand Colors
  static const Color sutOrange = Color(0xFFF57C00);
  static const Color sutBlue = Color(0xFF1976D2);
  
  // Neutral Colors - Light
  static const Color lightBg = Color(0xFFF8F9FA);
  static const Color lightSurface = Colors.white;
  static const Color lightTextPrimary = Color(0xFF1A1C1E);
  static const Color lightTextSecondary = Color(0xFF42474E);

  // Neutral Colors - Dark
  static const Color darkBg = Color(0xFF0F1113);
  static const Color darkSurface = Color(0xFF1A1C1E);
  static const Color darkTextPrimary = Color(0xFFE2E2E6);
  static const Color darkTextSecondary = Color(0xFFC2C7CF);

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: sutOrange,
        primary: sutOrange,
        onPrimary: Colors.white,
        secondary: sutBlue,
        surface: lightBg,
        error: const Color(0xFFBA1A1A),
      ),
      scaffoldBackgroundColor: lightBg,
      textTheme: _buildTextTheme(base.textTheme, lightTextPrimary, lightTextSecondary),
      cardTheme: _buildCardTheme(lightSurface),
      appBarTheme: _buildAppBarTheme(lightSurface, lightTextPrimary),
      elevatedButtonTheme: _buildButtonTheme(),
      dividerTheme: const DividerThemeData(color: Color(0xFFDEE2E6), thickness: 1),
    );
  }

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: sutOrange,
        brightness: Brightness.dark,
        primary: sutOrange,
        onPrimary: Colors.black,
        secondary: const Color(0xFF90CAF9),
        surface: darkBg,
      ),
      scaffoldBackgroundColor: darkBg,
      textTheme: _buildTextTheme(base.textTheme, darkTextPrimary, darkTextSecondary),
      cardTheme: _buildCardTheme(darkSurface),
      appBarTheme: _buildAppBarTheme(darkBg, darkTextPrimary),
      elevatedButtonTheme: _buildButtonTheme(),
      dividerTheme: const DividerThemeData(color: Color(0xFF44474E), thickness: 1),
    );
  }

  static TextTheme _buildTextTheme(TextTheme base, Color primary, Color secondary) {
    return GoogleFonts.plusJakartaSansTextTheme(base).copyWith(
      displayLarge: GoogleFonts.plusJakartaSans(
        fontSize: 32, fontWeight: FontWeight.w800, color: primary, letterSpacing: -0.5,
      ),
      displayMedium: GoogleFonts.plusJakartaSans(
        fontSize: 28, fontWeight: FontWeight.w800, color: primary, letterSpacing: -0.5,
      ),
      titleLarge: GoogleFonts.plusJakartaSans(
        fontSize: 20, fontWeight: FontWeight.w700, color: primary,
      ),
      titleMedium: GoogleFonts.plusJakartaSans(
        fontSize: 16, fontWeight: FontWeight.w600, color: primary,
      ),
      bodyLarge: GoogleFonts.plusJakartaSans(
        fontSize: 16, fontWeight: FontWeight.w500, color: primary, height: 1.5,
      ),
      bodyMedium: GoogleFonts.plusJakartaSans(
        fontSize: 14, fontWeight: FontWeight.w500, color: secondary, height: 1.5,
      ),
      labelLarge: GoogleFonts.plusJakartaSans(
        fontSize: 14, fontWeight: FontWeight.w700, color: sutOrange,
      ),
    );
  }

  static CardThemeData _buildCardTheme(Color color) {
    return CardThemeData(
      color: color,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: sutOrange.withValues(alpha: 0.1), width: 1),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    );
  }

  static AppBarTheme _buildAppBarTheme(Color bg, Color text) {
    return AppBarTheme(
      backgroundColor: bg,
      foregroundColor: text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 20, fontWeight: FontWeight.w800, color: text,
      ),
    );
  }

  static ElevatedButtonThemeData _buildButtonTheme() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

// Keep backward compatibility for SutSmartBusApp class
final ThemeData lightThemeData = AppTheme.light;
final ThemeData darkThemeData = AppTheme.dark;
