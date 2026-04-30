enum LegalDocumentType {
  terms,
  privacy,
}

class LegalSection {
  final String heading;
  final List<String> paragraphs;

  const LegalSection({
    required this.heading,
    required this.paragraphs,
  });
}

class LegalDocumentContent {
  final String title;
  final String effectiveDate;
  final List<LegalSection> sections;

  const LegalDocumentContent({
    required this.title,
    required this.effectiveDate,
    required this.sections,
  });
}

LegalDocumentContent getLegalDocument(LegalDocumentType type) {
  switch (type) {
    case LegalDocumentType.terms:
      return const LegalDocumentContent(
        title: 'Terms of Service',
        effectiveDate: 'April 28, 2026',
        sections: [
          LegalSection(
            heading: '1. Acceptance of Terms',
            paragraphs: [
              'These Terms of Service govern your use of the SUT Smart Bus application and related services operated for the Suranaree University of Technology community.',
              'By using the app, you agree to these terms. If you do not agree, do not use the service.',
            ],
          ),
          LegalSection(
            heading: '2. Intended Use',
            paragraphs: [
              'The app is intended to provide campus bus locations, route information, air quality readings, notifications, and operational feedback features.',
              'You agree to use the app only for lawful, personal, academic, or operational purposes connected to the SUT Smart Bus service.',
            ],
          ),
          LegalSection(
            heading: '3. User Responsibilities',
            paragraphs: [
              'You must not misuse the app, interfere with service operation, attempt unauthorized access, reverse engineer restricted systems, or submit harmful or misleading data.',
              'If you submit feedback or operational reports, you are responsible for ensuring the information is accurate to the best of your knowledge.',
            ],
          ),
          LegalSection(
            heading: '4. Service Availability',
            paragraphs: [
              'Bus tracking, ETA, passenger, and air quality data may be delayed, approximate, incomplete, or temporarily unavailable.',
              'The service may be changed, paused, or discontinued at any time for maintenance, safety, research, or operational reasons.',
            ],
          ),
          LegalSection(
            heading: '5. Privacy and Data',
            paragraphs: [
              'Use of the app is also subject to the Privacy Policy, which explains how operational, device, and usage data may be collected and used.',
            ],
          ),
          LegalSection(
            heading: '6. Intellectual Property',
            paragraphs: [
              'The app interface, branding, route data, and related service materials remain the property of their respective owners unless stated otherwise.',
              'You may not copy, redistribute, or commercially exploit the service content except as permitted by law or written authorization.',
            ],
          ),
          LegalSection(
            heading: '7. Disclaimers',
            paragraphs: [
              'The service is provided on an as-is and as-available basis without guarantees of uninterrupted access, accuracy, or fitness for a particular purpose.',
              'Do not rely on the app as your sole source for urgent safety, transport, or environmental decisions.',
            ],
          ),
          LegalSection(
            heading: '8. Limitation of Liability',
            paragraphs: [
              'To the extent permitted by applicable law, the university, project team, and service operators are not liable for indirect, incidental, special, or consequential losses arising from app use or unavailability.',
            ],
          ),
          LegalSection(
            heading: '9. Changes to These Terms',
            paragraphs: [
              'These terms may be updated from time to time. Continued use of the app after an update means you accept the revised terms.',
            ],
          ),
          LegalSection(
            heading: '10. Contact',
            paragraphs: [
              'Questions about these terms should be directed to the SUT Smart Bus project administrators or the responsible university support channel.',
            ],
          ),
        ],
      );
    case LegalDocumentType.privacy:
      return const LegalDocumentContent(
        title: 'Privacy Policy',
        effectiveDate: 'April 28, 2026',
        sections: [
          LegalSection(
            heading: '1. Scope',
            paragraphs: [
              'This Privacy Policy explains how SUT Smart Bus may collect, use, store, and protect information when you use the mobile application and related services.',
            ],
          ),
          LegalSection(
            heading: '2. Information We May Collect',
            paragraphs: [
              'The app may process device identifiers, app settings, language and theme preferences, notification preferences, debug or diagnostic information, and service interaction data.',
              'If you enable location-dependent features, the app may process your device location to support maps, nearby bus information, and route-related functions.',
              'The service may also display operational data from buses and sensors, including GPS positions, passenger counts, and air quality telemetry.',
            ],
          ),
          LegalSection(
            heading: '3. How We Use Information',
            paragraphs: [
              'We use information to operate the app, provide bus tracking and environmental features, maintain service reliability, investigate technical issues, and improve the campus transit experience.',
              'Feedback or support submissions may be used to respond to reports, investigate incidents, and improve future releases.',
            ],
          ),
          LegalSection(
            heading: '4. Sharing of Information',
            paragraphs: [
              'Information may be shared with authorized university staff, service operators, infrastructure providers, or project maintainers only as needed to operate, secure, maintain, or improve the service.',
              'We do not sell personal information through this app.',
            ],
          ),
          LegalSection(
            heading: '5. Data Retention',
            paragraphs: [
              'Information is retained only for as long as reasonably necessary for operations, analytics, troubleshooting, research, compliance, or safety purposes.',
              'Retention periods may vary depending on the type of data and the needs of the service.',
            ],
          ),
          LegalSection(
            heading: '6. Security',
            paragraphs: [
              'Reasonable administrative and technical safeguards may be used to protect service data, but no system can guarantee absolute security.',
            ],
          ),
          LegalSection(
            heading: '7. Your Choices',
            paragraphs: [
              'You can manage some local app preferences such as theme, language, and notifications from the app settings.',
              'If you do not agree with this policy, you should not use the app.',
            ],
          ),
          LegalSection(
            heading: '8. Children and Sensitive Use',
            paragraphs: [
              'The app is intended for the university transport community and is not designed as a platform for children to independently submit personal information.',
              'Users should avoid sending sensitive personal, financial, medical, or confidential information through feedback features.',
            ],
          ),
          LegalSection(
            heading: '9. Policy Updates',
            paragraphs: [
              'This policy may be updated to reflect service, legal, security, or operational changes. Continued use after updates means you accept the revised policy.',
            ],
          ),
          LegalSection(
            heading: '10. Contact',
            paragraphs: [
              'For privacy questions or requests, contact the SUT Smart Bus project administrators or the responsible university support channel.',
            ],
          ),
        ],
      );
  }
}
