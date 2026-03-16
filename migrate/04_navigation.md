# 04 — Navigation & Routing

## Purpose
Migrate React Navigation 6 (Bottom Tabs + Stack Navigator) to Flutter's `go_router` with a `NavigationBar` (Material 3 bottom navigation).

## Source Files Being Replaced
- `App.js` (TabNavigator + Stack setup) → `lib/app.dart` + `lib/screens/shell_screen.dart`

---

## Current React Native Navigation Structure

```
App.js
├── ThemeProvider
│   └── LanguageProvider
│       └── NotificationProvider
│           └── DebugProvider
│               └── DataProvider
│                   └── ErrorBoundary
│                       └── ThemedApp
│                           └── NavigationContainer
│                               └── Stack.Navigator
│                                   ├── MainTabs (TabNavigator)
│                                   │   ├── Map (MapScreen)
│                                   │   ├── Routes (RoutesScreen)
│                                   │   ├── Air Quality (AirQualityScreen)
│                                   │   └── Settings (SettingsScreen)
│                                   ├── RouteEditor
│                                   ├── BusRouteAdmin
│                                   ├── BusManagement
│                                   ├── AirQualityDashboard
│                                   └── About
```

---

## Flutter Implementation

### `lib/app.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'config/app_theme.dart';
import 'providers/theme_provider.dart';
import 'screens/shell_screen.dart';
import 'screens/map_screen.dart';
import 'screens/routes_screen.dart';
import 'screens/air_quality_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/route_editor_screen.dart';
import 'screens/bus_route_admin_screen.dart';
import 'screens/bus_management_screen.dart';
import 'screens/air_quality_dashboard_screen.dart';
import 'screens/about_screen.dart';

// Navigation keys for each tab branch
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final goRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/map',
  routes: [
    // Shell route wraps the bottom navigation tabs
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => ShellScreen(child: child),
      routes: [
        GoRoute(
          path: '/map',
          name: 'map',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: MapScreen(),
          ),
        ),
        GoRoute(
          path: '/routes',
          name: 'routes',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: RoutesScreen(),
          ),
        ),
        GoRoute(
          path: '/air-quality',
          name: 'airQuality',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: AirQualityScreen(),
          ),
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsScreen(),
          ),
        ),
      ],
    ),
    // Stack screens (pushed on top of tabs)
    GoRoute(
      path: '/route-editor',
      name: 'routeEditor',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final routeId = state.uri.queryParameters['routeId'];
        return RouteEditorScreen(routeId: routeId);
      },
    ),
    GoRoute(
      path: '/bus-route-admin',
      name: 'busRouteAdmin',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const BusRouteAdminScreen(),
    ),
    GoRoute(
      path: '/bus-management',
      name: 'busManagement',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const BusManagementScreen(),
    ),
    GoRoute(
      path: '/air-quality-dashboard',
      name: 'airQualityDashboard',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AirQualityDashboardScreen(),
    ),
    GoRoute(
      path: '/about',
      name: 'about',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const AboutScreen(),
    ),
  ],
);

class SutSmartBusApp extends ConsumerWidget {
  const SutSmartBusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'SUT Smart Bus',
      debugShowCheckedModeBanner: false,
      theme: lightThemeData,
      darkTheme: darkThemeData,
      themeMode: themeState.isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: goRouter,
    );
  }
}
```

### `lib/screens/shell_screen.dart` (Bottom Navigation Shell)

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/debug_provider.dart';

class ShellScreen extends ConsumerWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});

  // Map tab index to route path
  static const _tabs = ['/map', '/routes', '/air-quality', '/settings'];
  static const _icons = [
    Icons.map_outlined,
    Icons.list_alt,
    Icons.cloud_outlined,
    Icons.settings_outlined,
  ];
  static const _selectedIcons = [
    Icons.map,
    Icons.list_alt,
    Icons.cloud,
    Icons.settings,
  ];
  static const _labels = ['Map', 'Routes', 'Air Quality', 'Settings'];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    for (int i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i])) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = _currentIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          if (index != currentIndex) {
            context.go(_tabs[index]);
          }
        },
        destinations: List.generate(_tabs.length, (i) {
          return NavigationDestination(
            icon: Icon(_icons[i]),
            selectedIcon: Icon(_selectedIcons[i]),
            label: _labels[i],
          );
        }),
      ),
    );
  }
}
```

---

## Navigation Mapping (React Native → Flutter)

| React Native | Flutter |
|---|---|
| `navigation.navigate('Map', { selectedRoute, focusBus })` | `context.go('/map?routeId=xxx&busId=yyy')` or use `state.extra` |
| `navigation.navigate('RouteEditor', { routeId })` | `context.push('/route-editor?routeId=xxx')` |
| `navigation.navigate('BusRouteAdmin')` | `context.push('/bus-route-admin')` |
| `navigation.navigate('BusManagement')` | `context.push('/bus-management')` |
| `navigation.navigate('AirQualityDashboard')` | `context.push('/air-quality-dashboard')` |
| `navigation.navigate('About')` | `context.push('/about')` |
| `navigation.goBack()` | `context.pop()` |

### Passing complex data between screens

For complex objects like `selectedRoute` and `focusBus`, use `go_router`'s `extra` parameter:

```dart
// Pushing with data
context.push('/map', extra: {
  'selectedRoute': routeObject,
  'focusBus': busObject,
});

// Receiving in the screen
class MapScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    final selectedRoute = extra?['selectedRoute'] as BusRoute?;
    final focusBus = extra?['focusBus'] as Bus?;
  }
}
```

---

## Verification Checklist

- [ ] Bottom navigation renders with 4 tabs: Map, Routes, Air Quality, Settings
- [ ] Tapping each tab switches the view without animation (NoTransitionPage)
- [ ] Stack screens (RouteEditor, BusManagement, etc.) push ON TOP of the tab bar
- [ ] `context.pop()` returns to the previous screen correctly
- [ ] Active tab indicator uses the SUT Orange primary color
- [ ] Tab icons match the original: map, list, cloud, settings
