# 03 — Theming, Colors, Typography & Dark Mode

## Purpose
Migrate the React Native theme system (`ThemeContext.js`) to Flutter's built-in `ThemeData` system, maintaining the SUT Orange brand identity and dark mode support.

## Source Files Being Replaced
- `contexts/ThemeContext.js` → `lib/config/app_theme.dart` + `lib/providers/theme_provider.dart`

---

## Current React Native Theme (Source of Truth)

### Light Theme
```javascript
{
  background: '#ffffff',
  surface: '#f5f5f5',
  card: '#ffffff',
  text: '#333333',
  textSecondary: '#666666',
  textMuted: '#999999',
  primary: '#F57C00',        // SUT Orange
  primaryLight: '#FFF3E0',   // Light orange tint
  border: '#eeeeee',
  tabBar: '#ffffff',
  tabBarBorder: '#eeeeee',
}
```

### Dark Theme
```javascript
{
  background: '#121212',
  surface: '#1e1e1e',
  card: '#252525',
  text: '#ffffff',
  textSecondary: '#b0b0b0',
  textMuted: '#707070',
  primary: '#FFB74D',        // Lighter orange for dark mode
  primaryLight: '#3D2A1A',   // Dark orange tint
  border: '#333333',
  tabBar: '#1e1e1e',
  tabBarBorder: '#333333',
}
```

---

## Flutter Implementation

### `lib/config/app_theme.dart`

```dart
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
  colorScheme: ColorScheme.light(
    primary: _lightPrimary,
    onPrimary: _lightOnPrimary,
    surface: const Color(0xFFFFFFFF),
    onSurface: const Color(0xFF333333),
    secondary: _lightPrimary,
    outline: const Color(0xFFEEEEEE),
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
  colorScheme: ColorScheme.dark(
    primary: _darkPrimary,
    onPrimary: Colors.black,
    surface: const Color(0xFF121212),
    onSurface: const Color(0xFFFFFFFF),
    secondary: _darkPrimary,
    outline: const Color(0xFF333333),
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
```

---

## How to Use in Widgets

### Accessing theme (replaces `useTheme()` hook)

```dart
// In React Native:
// const { theme, isDark } = useTheme();
// style={{ color: theme.text }}

// In Flutter:
final theme = Theme.of(context);
final appColors = theme.extension<AppColors>()!;

// Usage:
Text('Hello', style: TextStyle(color: theme.colorScheme.onSurface)); // text
Container(color: appColors.surface);                                   // surface
Text('Muted', style: TextStyle(color: appColors.textMuted));          // textMuted
Container(color: theme.colorScheme.primary);                           // primary
Container(color: appColors.primaryLight);                              // primaryLight
```

### Toggling theme (replaces `toggleTheme()`)

```dart
// In a widget using Riverpod:
final themeState = ref.watch(themeProvider);
final themeNotifier = ref.read(themeProvider.notifier);

Switch(
  value: themeState.isDark,
  onChanged: (_) => themeNotifier.toggleTheme(),
);
```

---

## Verification Checklist

- [ ] Light theme renders SUT Orange (#F57C00) as primary color
- [ ] Dark theme renders lighter orange (#FFB74D) as primary color
- [ ] Theme toggle persists across app restarts (SharedPreferences)
- [ ] `AppColors` extension is accessible via `Theme.of(context).extension<AppColors>()`
- [ ] Google Fonts (Inter) loads correctly
- [ ] All screen text colors match the React Native app's appearance
