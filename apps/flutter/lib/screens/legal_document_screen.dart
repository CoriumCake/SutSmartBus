import 'package:flutter/material.dart';

import '../legal/legal_documents.dart';

class LegalDocumentScreen extends StatelessWidget {
  final LegalDocumentType type;

  const LegalDocumentScreen({
    super.key,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final document = getLegalDocument(type);

    return Scaffold(
      appBar: AppBar(
        title: Text(document.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            document.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Effective date: ${document.effectiveDate}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          ...document.sections.map(
            (section) => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.heading,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...section.paragraphs.map(
                        (paragraph) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SelectableText(
                            paragraph,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
