import 'dart:io' show exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import '../legal/legal_documents.dart';
import '../providers/legal_consent_provider.dart';

enum _ConsentStep {
  terms,
  privacy,
}

class LegalConsentScreen extends ConsumerStatefulWidget {
  const LegalConsentScreen({super.key});

  @override
  ConsumerState<LegalConsentScreen> createState() => _LegalConsentScreenState();
}

class _LegalConsentScreenState extends ConsumerState<LegalConsentScreen> {
  bool _submitting = false;
  _ConsentStep _step = _ConsentStep.terms;

  Future<void> _accept() async {
    if (_submitting) return;

    if (_step == _ConsentStep.terms) {
      setState(() => _step = _ConsentStep.privacy);
      return;
    }

    setState(() => _submitting = true);

    await ref.read(legalConsentProvider.notifier).accept();
    if (!mounted) return;

    context.go('/map');
  }

  Future<void> _decline() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    await ref.read(legalConsentProvider.notifier).decline();
    if (!mounted) return;

    if (kIsWeb) {
      setState(() => _submitting = false);
      return;
    }

    await SystemNavigator.pop();
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTermsStep = _step == _ConsentStep.terms;
    final document = getLegalDocument(
      isTermsStep ? LegalDocumentType.terms : LegalDocumentType.privacy,
    );

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color:
                                    AppTheme.sutOrange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.verified_user_outlined,
                                color: AppTheme.sutOrange,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isTermsStep ? 'Step 1 of 2' : 'Step 2 of 2',
                                    style: theme.textTheme.labelLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    document.title,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          isTermsStep
                              ? 'Read the Terms of Service to continue.'
                              : 'Read the Privacy Policy to finish setup.',
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Effective date: ${document.effectiveDate}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 420),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Scrollbar(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final section in document.sections) ...[
                                    Text(
                                      section.heading,
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    for (final paragraph in section.paragraphs)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: SelectableText(
                                          paragraph,
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      ),
                                    const SizedBox(height: 8),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            isTermsStep
                                ? 'Accept the Terms of Service to continue to the Privacy Policy.'
                                : 'Accept the Privacy Policy to enter the app. Declining will close the app and ask again next time.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _submitting ? null : _decline,
                                child: const Text('Decline'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _submitting ? null : _accept,
                                child: Text(
                                  _submitting
                                      ? 'Please wait...'
                                      : isTermsStep
                                          ? 'Accept Terms'
                                          : 'Accept Privacy Policy',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
