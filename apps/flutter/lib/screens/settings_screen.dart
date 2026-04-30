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
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),

          // ─── Appearance ─────────────────────────
          _sectionCard(
            theme,
            icon: Icons.palette,
            title: t('darkMode'),
            trailing: Switch(
              value: themeState.isDark,
              onChanged: (_) => ref.read(themeProvider.notifier).toggleTheme(),
              activeThumbColor: theme.colorScheme.primary,
            ),
          ),

          // ─── Notifications ──────────────────────
          _sectionCard(
            theme,
            icon: Icons.notifications_none,
            title: t('notifications'),
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
                activeThumbColor: theme.colorScheme.primary,
              );
            }),
          ),

          // ─── Language ───────────────────────────
          _sectionCard(
            theme,
            icon: Icons.language,
            title: t('language'),
            trailing: Text(langState.language == 'th' ? 'ไทย' : 'English',
                style: TextStyle(color: theme.colorScheme.primary)),
            onTap: () => _showLanguageDialog(context, ref),
          ),

          // ─── Debug Mode ─────────────────────────
          if (debugState.isDevMachine) ...[
            _sectionCard(
              theme,
              icon: Icons.bug_report,
              title: t('debugMode'),
              trailing: Switch(
                value: debugState.debugMode,
                onChanged: (_) =>
                    ref.read(debugProvider.notifier).toggleDebug(),
                activeThumbColor: Colors.red,
              ),
            ),
            _sectionCard(
              theme,
              icon: Icons.build,
              title: 'Testing & Debug Tools',
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/testing'),
            ),
            _sectionCard(
              theme,
              icon: Icons.developer_mode,
              title: 'Developer Mode',
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/developer'),
            ),
          ],

          const SizedBox(height: 20),

          // ─── Navigation Links ───────────────────
          _sectionCard(
            theme,
            icon: Icons.directions_bus,
            title: t('busManagement'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/bus-management'),
          ),
          _sectionCard(
            theme,
            icon: Icons.map,
            title: t('routeAdmin'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/bus-route-admin'),
          ),
          _sectionCard(
            theme,
            icon: Icons.info_outline,
            title: t('about'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/about'),
          ),
          _sectionCard(
            theme,
            icon: Icons.description_outlined,
            title: 'Terms of Service',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/legal-document?type=terms'),
          ),
          _sectionCard(
            theme,
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/legal-document?type=privacy'),
          ),
          _sectionCard(
            theme,
            icon: Icons.feedback_outlined,
            title: 'Feedback',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/feedback'),
          ),

          // ─── Debug Info ─────────────────────────
          if (debugState.debugMode) ...[
            const SizedBox(height: 20),
            Text('Developer',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('API', ApiConfig.baseUrl),
                    _infoRow(
                        'Mode',
                        ApiConfig.baseUrl.contains('tunnel')
                            ? 'Tunnel'
                            : 'Local'),
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

  Widget _sectionCard(
    ThemeData theme, {
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
          Flexible(
              child: Text(value,
                  style: const TextStyle(fontSize: 12),
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
