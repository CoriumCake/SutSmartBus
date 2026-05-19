import 'package:flutter/material.dart';

import '../legal/legal_documents.dart';

class LegalDocumentScreen extends StatefulWidget {
  final LegalDocumentType type;

  const LegalDocumentScreen({
    super.key,
    required this.type,
  });

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  LegalDocumentLanguage _language = LegalDocumentLanguage.th;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final document = getLegalDocument(
      widget.type,
      language: _language,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(document.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 32),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              document.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
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
                onSelectionChanged: (selection) {
                  setState(() => _language = selection.first);
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          ...document.sections.map(
            (section) => Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
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
        ],
      ),
    );
  }
}
