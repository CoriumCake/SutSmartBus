import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';

class ShellScreen extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const ShellScreen({super.key, required this.navigationShell});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = navigationShell.currentIndex;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B1714) : const Color(0xFFFFF7F0),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: AppTheme.sutOrange.withValues(alpha: isDark ? 0.18 : 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Colors.transparent,
            height: 74,
            indicatorColor: AppTheme.sutOrange.withValues(alpha: 0.16),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return theme.textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected
                    ? AppTheme.sutOrange
                    : (isDark
                        ? const Color(0xFFC9B8AB)
                        : const Color(0xFF7A6556)),
              );
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return IconThemeData(
                size: selected ? 25 : 23,
                color: selected
                    ? AppTheme.sutOrange
                    : (isDark
                        ? const Color(0xFFC9B8AB)
                        : const Color(0xFF7A6556)),
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: (index) {
              navigationShell.goBranch(
                index,
                initialLocation: index == currentIndex,
              );
            },
            destinations: List.generate(_tabs.length, (i) {
              return NavigationDestination(
                icon: Icon(_icons[i]),
                selectedIcon: Icon(_selectedIcons[i]),
                label: _labels[i],
              );
            }),
          ),
        ),
      ),
    );
  }
}
