import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_theme.dart';

class ThemeState {
  final bool isDark;
  final ThemeData themeData;

  ThemeState({required this.isDark, required this.themeData});
}

class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier() : super(ThemeState(isDark: false, themeData: lightThemeData)) {
    _loadSavedTheme();
  }

  Future<void> _loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('app_theme');
    if (savedTheme == 'dark') {
      state = ThemeState(isDark: true, themeData: darkThemeData);
    }
  }

  Future<void> toggleTheme() async {
    final newIsDark = !state.isDark;
    state = ThemeState(
      isDark: newIsDark,
      themeData: newIsDark ? darkThemeData : lightThemeData,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme', newIsDark ? 'dark' : 'light');
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier();
});
