import 'dart:io' show exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  LegalDocumentLanguage _language = LegalDocumentLanguage.th;

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
      language: _language,
    );
    final isThai = _language == LegalDocumentLanguage.th;
    final acceptLabel = _submitting
        ? isThai
            ? 'กำลังดำเนินการ...'
            : 'Please wait...'
        : isTermsStep
            ? isThai
                ? 'ยินยอม'
                : 'Accept Terms'
            : isThai
                ? 'ยินยอม'
                : 'Accept';

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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          document.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: SegmentedButton<LegalDocumentLanguage>(
                            segments: const [
                              ButtonSegment(
                                value: LegalDocumentLanguage.th,
                                label: Text('ไทย'),
                              ),
                              ButtonSegment(
                                value: LegalDocumentLanguage.en,
                                label: Text('English'),
                              ),
                            ],
                            selected: {_language},
                            onSelectionChanged: _submitting
                                ? null
                                : (selection) {
                                    setState(
                                      () => _language = selection.first,
                                    );
                                  },
                          ),
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
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _submitting ? null : _decline,
                                child: Text(isThai ? 'ปฏิเสธ' : 'Decline'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _submitting ? null : _accept,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    acceptLabel,
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
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
