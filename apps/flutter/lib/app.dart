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
import 'screens/testing_screen.dart';
import 'screens/feedback_screen.dart';
import 'screens/developer_mode_screen.dart';

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
    GoRoute(
      path: '/testing',
      name: 'testing',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const TestingScreen(),
    ),
    GoRoute(
      path: '/feedback',
      name: 'feedback',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const FeedbackScreen(),
    ),
    GoRoute(
      path: '/developer',
      name: 'developer',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const DeveloperModeScreen(),
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
