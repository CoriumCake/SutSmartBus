import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy & Policies'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Privacy Policy',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Last updated: April 2026',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            
            _buildSection(
              theme,
              title: '1. Information We Collect',
              content: 'We collect information to provide better services to all our users. '
                  'The SUT Smart Bus app requires access to your location data to show you '
                  'nearby buses and stops. We may also collect anonymous usage data to '
                  'improve the app experience.',
            ),
            
            _buildSection(
              theme,
              title: '2. How We Use Information',
              content: 'Your location data is used solely within the app to calculate distances '
                  'to stops and estimate bus arrival times. We do not store your location '
                  'history on our servers, nor do we share it with third parties.',
            ),
            
            _buildSection(
              theme,
              title: '3. Device Permissions',
              content: 'To use certain features, the app requests permission to access your '
                  'device\'s location. You can revoke these permissions at any time through '
                  'your device settings, though some features may become unavailable.',
            ),
            
            _buildSection(
              theme,
              title: '4. Data Security',
              content: 'We work hard to protect SUT Smart Bus and our users from unauthorized '
                  'access to or unauthorized alteration, disclosure, or destruction of '
                  'information we hold.',
            ),
            
            _buildSection(
              theme,
              title: '5. Changes to This Policy',
              content: 'Our Privacy Policy may change from time to time. We will post any '
                  'privacy policy changes on this page and, if the changes are significant, '
                  'we will provide a more prominent notice.',
            ),
            
            const SizedBox(height: 40),
            Center(
              child: Text(
                'SUT Smart Bus Team',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(ThemeData theme, {required String title, required String content}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}
