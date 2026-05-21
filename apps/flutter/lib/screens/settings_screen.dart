import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/language_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final langState = ref.watch(languageProvider);
    final theme = Theme.of(context);
    final t = langState.t;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            t('settings'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _sectionHeader(theme, 'General'),
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
          _sectionCard(
            theme,
            icon: Icons.notifications_none,
            title: t('notifications'),
            trailing: Consumer(
              builder: (context, ref, _) {
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
              },
            ),
          ),
          _sectionCard(
            theme,
            icon: Icons.language,
            title: t('language'),
            trailing: Text(
              langState.language == 'th' ? 'ไทย' : 'English',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
            onTap: () => _showLanguageDialog(context, ref),
          ),
          const SizedBox(height: 20),
          _sectionHeader(theme, 'Developer'),
          _sectionCard(
            theme,
            icon: Icons.code,
            title: 'Developer',
            subtitle: 'Debug tools and operational toggles',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/developer-settings'),
          ),
          const SizedBox(height: 20),
          _sectionHeader(theme, 'Support'),
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
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _sectionCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: trailing,
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
