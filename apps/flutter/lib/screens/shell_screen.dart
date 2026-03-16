import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
