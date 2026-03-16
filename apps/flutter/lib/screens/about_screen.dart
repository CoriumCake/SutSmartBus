import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/language_provider.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(languageProvider).t;

    return Scaffold(
      appBar: AppBar(title: Text(t('about'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Logo
          Center(child: Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(24)),
            child: const Icon(Icons.directions_bus, size: 48, color: Colors.white),
          )),
          const SizedBox(height: 16),
          Center(child: Text('SUT Smart Bus',
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold))),
          Center(child: Text('${t("version")} 1.0.0',
              style: theme.textTheme.bodySmall)),
          const SizedBox(height: 24),

          // Description
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(t('appDescription'), style: theme.textTheme.bodyMedium),
            ),
          ),
          const SizedBox(height: 16),

          // Features
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _featureRow(Icons.location_on, 'Real-time bus tracking', theme.colorScheme.primary),
                _featureRow(Icons.eco, 'Air quality monitoring (PM2.5)', Colors.green),
                _featureRow(Icons.notifications, 'Arrival notifications', Colors.amber),
                _featureRow(Icons.map, 'Route visualization', Colors.purple),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Developer
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Development Team', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text('Suranaree University of Technology'),
                const Text('School of Computer Engineering'),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Contact
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Contact & Support', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _linkRow(Icons.mail, 'support@sut.ac.th', 'mailto:support@sut.ac.th', theme),
                _linkRow(Icons.language, 'www.sut.ac.th', 'https://www.sut.ac.th', theme),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          Center(child: Text('© 2024 Suranaree University of Technology',
              style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }

  Widget _featureRow(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(text),
      ]),
    );
  }

  Widget _linkRow(IconData icon, String label, String url, ThemeData theme) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: theme.colorScheme.primary)),
        ]),
      ),
    );
  }
}
