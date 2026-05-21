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
import 'screens/air_quality_dashboard_screen.dart';
import 'screens/about_screen.dart';
import 'screens/feedback_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/legal_consent_screen.dart';
import 'screens/legal_document_screen.dart';
import 'screens/passenger_stats_screen.dart';
import 'screens/developer_settings_screen.dart';
import 'screens/wifi_heatmap_screen.dart';
import 'legal/legal_documents.dart';

// Navigation keys for each tab branch
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _mapNavigatorKey = GlobalKey<NavigatorState>();
final _routesNavigatorKey = GlobalKey<NavigatorState>();
final _airQualityNavigatorKey = GlobalKey<NavigatorState>();
final _settingsNavigatorKey = GlobalKey<NavigatorState>();

final goRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      name: 'splash',
      pageBuilder: (context, state) => const NoTransitionPage(
        child: SplashScreen(),
      ),
    ),
    GoRoute(
      path: '/legal-consent',
      name: 'legalConsent',
      pageBuilder: (context, state) => const NoTransitionPage(
        child: LegalConsentScreen(),
      ),
    ),
    GoRoute(
      path: '/legal-document',
      name: 'legalDocument',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final type = state.uri.queryParameters['type'] == 'privacy'
            ? LegalDocumentType.privacy
            : LegalDocumentType.terms;
        return LegalDocumentScreen(type: type);
      },
    ),
    // Keep each bottom tab alive so map/heatmap state survives tab switches.
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          ShellScreen(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          navigatorKey: _mapNavigatorKey,
          routes: [
            GoRoute(
              path: '/map',
              name: 'map',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: MapScreen(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _routesNavigatorKey,
          routes: [
            GoRoute(
              path: '/routes',
              name: 'routes',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: RoutesScreen(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _airQualityNavigatorKey,
          routes: [
            GoRoute(
              path: '/air-quality',
              name: 'airQuality',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: AirQualityScreen(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _settingsNavigatorKey,
          routes: [
            GoRoute(
              path: '/settings',
              name: 'settings',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: SettingsScreen(),
              ),
            ),
          ],
        ),
      ],
    ),
    // Stack screens (pushed on top of tabs)
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
      path: '/feedback',
      name: 'feedback',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const FeedbackScreen(),
    ),
    GoRoute(
      path: '/passenger-stats',
      name: 'passengerStats',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const PassengerStatsScreen(),
    ),
    GoRoute(
      path: '/developer-settings',
      name: 'developerSettings',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const DeveloperSettingsScreen(),
    ),
    GoRoute(
      path: '/wifi-heatmap',
      name: 'wifiHeatmap',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const WifiHeatmapScreen(),
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
