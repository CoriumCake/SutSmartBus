import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import '../providers/debug_provider.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About SUT Smart Bus'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          // Header / Logo
          Center(
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.directions_bus,
                      size: 54, color: Colors.white),
                ),
                const SizedBox(height: 20),
                Text(
                  'SUT Smart Bus',
                  style: theme.textTheme.displayMedium,
                ),
                Text(
                  'Version 1.2.0 (Build 105)',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Consumer(
                  builder: (context, ref, child) {
                    final deviceId = ref.watch(debugProvider).deviceId;
                    if (deviceId == null) return const SizedBox.shrink();
                    return GestureDetector(
                      onLongPress: () {
                        Clipboard.setData(ClipboardData(text: deviceId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Device ID copied to clipboard')),
                        );
                      },
                      child: Text(
                        'Device ID: $deviceId',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),

          // Description Card
          _buildInfoCard(
            theme,
            'Description',
            'SUT Smart Bus is an advanced transit and environmental monitoring platform for Suranaree University of Technology. It provides real-time bus tracking, PM2.5 air quality monitoring, and estimated arrival times for the campus community.',
          ),

          const SizedBox(height: 16),

          // Features Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Core Features', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 16),
                  _buildFeatureRow(Icons.location_on, 'Real-time GPS Tracking',
                      colorScheme.primary),
                  _buildFeatureRow(
                      Icons.eco, 'Live PM2.5 Monitoring', Colors.green),
                  _buildFeatureRow(
                      Icons.timer, 'Smart ETA Predictions', Colors.blue),
                  _buildFeatureRow(
                      Icons.map, 'Interactive Route Maps', Colors.purple),
                  _buildFeatureRow(Icons.notifications_active,
                      'Arrival Notifications', Colors.orange),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Developer Card
          _buildInfoCard(
            theme,
            'Development Team',
            'Developed by the School of Computer Engineering, Suranaree University of Technology. Optimized for modern campus transit management.',
          ),

          const SizedBox(height: 16),

          // Contact & Links
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connect with us', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 16),
                  _buildLinkRow(theme, Icons.language, 'Official Website',
                      'https://www.sut.ac.th'),
                  _buildLinkRow(theme, Icons.email, 'Technical Support',
                      'mailto:support@sut.ac.th'),
                  _buildLinkRow(theme, Icons.code, 'Project Repository',
                      'https://github.com/SUT-Smart-Bus'),
                  _buildNavigationRow(
                    context,
                    theme,
                    Icons.description_outlined,
                    'Terms of Service',
                    '/legal-document?type=terms',
                  ),
                  _buildNavigationRow(
                    context,
                    theme,
                    Icons.privacy_tip_outlined,
                    'Privacy Policy',
                    '/legal-document?type=privacy',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              '© 2026 Suranaree University of Technology',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, String title, String content) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(content, style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildLinkRow(
      ThemeData theme, IconData icon, String label, String url) {
    return InkWell(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Icon(icon, size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Icon(Icons.open_in_new,
                size: 16,
                color: theme.colorScheme.primary.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationRow(
    BuildContext context,
    ThemeData theme,
    IconData icon,
    String label,
    String route,
  ) {
    return InkWell(
      onTap: () => context.push(route),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Icon(icon, size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
