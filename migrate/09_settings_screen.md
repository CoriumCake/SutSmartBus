# 09 — Settings Screen Migration

## Purpose
Migrate `SettingsScreen.js` (295 lines) — the app preferences screen with dark mode, language, notifications, debug features, and developer info.

## Source File
- `screens/SettingsScreen.js` → `lib/screens/settings_screen.dart`
- `contexts/LanguageContext.js` → `lib/providers/language_provider.dart`
- `contexts/DebugContext.js` → `lib/providers/debug_provider.dart`
- `contexts/NotificationContext.js` → `lib/providers/notification_provider.dart`

---

## Current React Native Settings Items

1. **Appearance** → Dark mode toggle
2. **Notifications** → Enable/disable notifications toggle
3. **Language** → Modal selector (English / ไทย)
4. **Debug Mode** → Toggle (only on allowlisted devices)
5. **Developer section** (when debug mode active):
   - API endpoint URL display
   - API authentication status
   - API key check button
   - Device ID display
   - API request counter
   - Connection mode (local/tunnel)
6. **Navigation links**:
   - Bus Management → pushes BusManagementScreen
   - Route Admin → pushes BusRouteAdminScreen
   - About → pushes AboutScreen

---

## Flutter Implementation

### `lib/providers/language_provider.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageState {
  final String language; // 'en' or 'th'
  final Map<String, String> translations;

  LanguageState({required this.language, required this.translations});

  String t(String key) => translations[key] ?? key;
}

class LanguageNotifier extends StateNotifier<LanguageState> {
  LanguageNotifier() : super(LanguageState(
    language: 'en',
    translations: _enTranslations,
  )) {
    _loadSavedLanguage();
  }

  Future<void> _loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString('app_language') ?? 'en';
    state = LanguageState(
      language: savedLang,
      translations: savedLang == 'th' ? _thTranslations : _enTranslations,
    );
  }

  Future<void> changeLanguage(String lang) async {
    state = LanguageState(
      language: lang,
      translations: lang == 'th' ? _thTranslations : _enTranslations,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', lang);
  }
}

final languageProvider = StateNotifierProvider<LanguageNotifier, LanguageState>((ref) {
  return LanguageNotifier();
});

// ─── Translations ───────────────────────────────────

const _enTranslations = {
  'routes': 'Routes',
  'settings': 'Settings',
  'darkMode': 'Dark Mode',
  'notifications': 'Notifications',
  'language': 'Language',
  'debugMode': 'Debug Mode',
  'about': 'About',
  'busManagement': 'Bus Management',
  'routeAdmin': 'Bus Route Admin',
  'airQuality': 'Air Quality',
  'version': 'Version',
  'appDescription': 'Smart transit & environmental monitoring for Suranaree University of Technology.',
  'noActiveBuses': 'No active buses',
  'refresh': 'Refresh',
  'selectLanguage': 'Select Language',
  // Add more as needed
};

const _thTranslations = {
  'routes': 'เส้นทาง',
  'settings': 'ตั้งค่า',
  'darkMode': 'โหมดมืด',
  'notifications': 'การแจ้งเตือน',
  'language': 'ภาษา',
  'debugMode': 'โหมดดีบัก',
  'about': 'เกี่ยวกับ',
  'busManagement': 'จัดการรถบัส',
  'routeAdmin': 'จัดการเส้นทาง',
  'airQuality': 'คุณภาพอากาศ',
  'version': 'เวอร์ชัน',
  'appDescription': 'ระบบขนส่งอัจฉริยะและตรวจสอบสิ่งแวดล้อมสำหรับมหาวิทยาลัยเทคโนโลยีสุรนารี',
  'noActiveBuses': 'ไม่มีรถบัสที่ใช้งาน',
  'refresh': 'รีเฟรช',
  'selectLanguage': 'เลือกภาษา',
};
```

### `lib/providers/debug_provider.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;
import '../config/allowed_devices.dart';

class DebugState {
  final bool debugMode;
  final bool isDevMachine;
  final String? deviceId;
  final int apiCallCount;

  DebugState({
    this.debugMode = false,
    this.isDevMachine = false,
    this.deviceId,
    this.apiCallCount = 0,
  });

  DebugState copyWith({bool? debugMode, bool? isDevMachine, String? deviceId, int? apiCallCount}) {
    return DebugState(
      debugMode: debugMode ?? this.debugMode,
      isDevMachine: isDevMachine ?? this.isDevMachine,
      deviceId: deviceId ?? this.deviceId,
      apiCallCount: apiCallCount ?? this.apiCallCount,
    );
  }
}

class DebugNotifier extends StateNotifier<DebugState> {
  DebugNotifier() : super(DebugState()) {
    _checkDevice();
  }

  Future<void> _checkDevice() async {
    final deviceInfo = DeviceInfoPlugin();
    String? deviceId;

    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      deviceId = info.id;
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      deviceId = info.identifierForVendor;
    }

    final isAllowed = allowedDeviceIds.contains(deviceId);
    state = state.copyWith(
      deviceId: deviceId,
      isDevMachine: isAllowed,
      debugMode: isAllowed,
    );
  }

  void toggleDebug() {
    if (state.isDevMachine) {
      state = state.copyWith(debugMode: !state.debugMode);
    }
  }

  void incrementApiCount() {
    state = state.copyWith(apiCallCount: state.apiCallCount + 1);
  }
}

final debugProvider = StateNotifierProvider<DebugNotifier, DebugState>((ref) {
  return DebugNotifier();
});
```

### `lib/screens/settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/theme_provider.dart';
import '../providers/language_provider.dart';
import '../providers/debug_provider.dart';
import '../providers/notification_provider.dart';
import '../config/api_config.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final langState = ref.watch(languageProvider);
    final debugState = ref.watch(debugProvider);
    final theme = Theme.of(context);
    final t = langState.t;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header
          Text(t('settings'),
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),

          // ─── Appearance ─────────────────────────
          _sectionCard(theme, icon: Icons.palette, title: t('darkMode'),
            trailing: Switch(
              value: themeState.isDark,
              onChanged: (_) => ref.read(themeProvider.notifier).toggleTheme(),
              activeColor: theme.colorScheme.primary,
            ),
          ),

          // ─── Notifications ──────────────────────
          _sectionCard(theme, icon: Icons.notifications_none, title: t('notifications'),
            trailing: Consumer(builder: (context, ref, _) {
              final notifState = ref.watch(notificationProvider);
              return Switch(
                value: notifState.enabled,
                onChanged: (val) {
                  if (val) {
                    ref.read(notificationProvider.notifier).enable();
                  } else {
                    ref.read(notificationProvider.notifier).disable();
                  }
                },
                activeColor: theme.colorScheme.primary,
              );
            }),
          ),

          // ─── Language ───────────────────────────
          _sectionCard(theme, icon: Icons.language, title: t('language'),
            trailing: Text(langState.language == 'th' ? 'ไทย' : 'English',
                style: TextStyle(color: theme.colorScheme.primary)),
            onTap: () => _showLanguageDialog(context, ref),
          ),

          // ─── Debug Mode ─────────────────────────
          if (debugState.isDevMachine)
            _sectionCard(theme, icon: Icons.bug_report, title: t('debugMode'),
              trailing: Switch(
                value: debugState.debugMode,
                onChanged: (_) => ref.read(debugProvider.notifier).toggleDebug(),
                activeColor: Colors.red,
              ),
            ),

          const SizedBox(height: 20),

          // ─── Navigation Links ───────────────────
          _sectionCard(theme, icon: Icons.directions_bus, title: t('busManagement'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/bus-management'),
          ),
          _sectionCard(theme, icon: Icons.map, title: t('routeAdmin'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/bus-route-admin'),
          ),
          _sectionCard(theme, icon: Icons.info_outline, title: t('about'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/about'),
          ),

          // ─── Debug Info ─────────────────────────
          if (debugState.debugMode) ...[
            const SizedBox(height: 20),
            Text('Developer', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('API', ApiConfig.baseUrl),
                    _infoRow('Mode', ApiConfig.baseUrl.contains('tunnel') ? 'Tunnel' : 'Local'),
                    _infoRow('Device ID', debugState.deviceId ?? 'Unknown'),
                    _infoRow('API Calls', '${debugState.apiCallCount}'),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionCard(ThemeData theme, {
    required IconData icon,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        trailing: trailing,
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Flexible(child: Text(value, style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Language'),
        children: [
          SimpleDialogOption(
            child: const Text('English'),
            onPressed: () {
              ref.read(languageProvider.notifier).changeLanguage('en');
              Navigator.pop(ctx);
            },
          ),
          SimpleDialogOption(
            child: const Text('ไทย'),
            onPressed: () {
              ref.read(languageProvider.notifier).changeLanguage('th');
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }
}
```

---

## Verification Checklist

- [ ] Dark mode toggle switches theme and persists across restarts
- [ ] Language toggle switches all visible strings between English and Thai
- [ ] Notification toggle enables/disables notifications
- [ ] Debug mode toggle only appears on allowlisted devices
- [ ] Navigation links (Bus Management, Route Admin, About) push correct screens
- [ ] Debug info section shows API endpoint, mode, device ID, API call count
