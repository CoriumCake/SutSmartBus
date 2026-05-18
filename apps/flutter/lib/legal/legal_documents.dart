enum LegalDocumentType {
  terms,
  privacy,
}

enum LegalDocumentLanguage {
  th,
  en,
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

LegalDocumentContent getLegalDocument(
  LegalDocumentType type, {
  LegalDocumentLanguage language = LegalDocumentLanguage.th,
}) {
  switch (type) {
    case LegalDocumentType.terms:
      return language == LegalDocumentLanguage.en ? _termsEn : _termsTh;
    case LegalDocumentType.privacy:
      return language == LegalDocumentLanguage.en ? _privacyEn : _privacyTh;
  }
}

const _termsTh = LegalDocumentContent(
  title: 'ข้อกำหนดการใช้บริการ',
  effectiveDate: 'April 28, 2026',
  sections: [
    LegalSection(
      heading: '1. การยอมรับข้อกำหนด',
      paragraphs: [
        'ข้อกำหนดการใช้บริการนี้ใช้กำกับการใช้งานแอปพลิเคชัน SUT Smart Bus และบริการที่เกี่ยวข้องสำหรับชุมชนมหาวิทยาลัยเทคโนโลยีสุรนารี',
        'เมื่อใช้งานแอป คุณยอมรับข้อกำหนดเหล่านี้ หากคุณไม่ยอมรับ โปรดงดใช้บริการ',
      ],
    ),
    LegalSection(
      heading: '2. วัตถุประสงค์การใช้งาน',
      paragraphs: [
        'แอปนี้มีวัตถุประสงค์เพื่อแสดงตำแหน่งรถบัสในมหาวิทยาลัย ข้อมูลเส้นทาง ค่าคุณภาพอากาศ การแจ้งเตือน และช่องทางส่งข้อเสนอแนะเกี่ยวกับการให้บริการ',
        'คุณตกลงใช้แอปเพื่อวัตถุประสงค์ที่ถูกต้องตามกฎหมาย เป็นการใช้งานส่วนบุคคล การศึกษา หรือการดำเนินงานที่เกี่ยวข้องกับบริการ SUT Smart Bus เท่านั้น',
      ],
    ),
    LegalSection(
      heading: '3. ความรับผิดชอบของผู้ใช้',
      paragraphs: [
        'คุณต้องไม่ใช้แอปในทางที่ผิด รบกวนการทำงานของบริการ พยายามเข้าถึงระบบโดยไม่ได้รับอนุญาต ถอดรหัสระบบที่จำกัดสิทธิ์ หรือส่งข้อมูลที่เป็นอันตรายหรือทำให้เข้าใจผิด',
        'หากคุณส่งข้อเสนอแนะหรือรายงานการดำเนินงาน คุณมีหน้าที่ตรวจสอบให้ข้อมูลถูกต้องตามที่คุณทราบ',
      ],
    ),
    LegalSection(
      heading: '4. ความพร้อมให้บริการ',
      paragraphs: [
        'ข้อมูลตำแหน่งรถบัส เวลาโดยประมาณ จำนวนผู้โดยสาร และค่าคุณภาพอากาศอาจล่าช้า เป็นค่าประมาณ ไม่ครบถ้วน หรือไม่พร้อมใช้งานชั่วคราว',
        'บริการอาจมีการเปลี่ยนแปลง หยุดพัก หรือยุติได้ทุกเมื่อเพื่อการบำรุงรักษา ความปลอดภัย การวิจัย หรือเหตุผลด้านการดำเนินงาน',
      ],
    ),
    LegalSection(
      heading: '5. ความเป็นส่วนตัวและข้อมูล',
      paragraphs: [
        'การใช้งานแอปอยู่ภายใต้นโยบายความเป็นส่วนตัว ซึ่งอธิบายวิธีที่ข้อมูลการดำเนินงาน อุปกรณ์ และการใช้งานอาจถูกเก็บรวบรวมและนำไปใช้',
      ],
    ),
    LegalSection(
      heading: '6. ทรัพย์สินทางปัญญา',
      paragraphs: [
        'ส่วนติดต่อผู้ใช้ เครื่องหมายทางการค้า ข้อมูลเส้นทาง และสื่อที่เกี่ยวข้องกับบริการเป็นทรัพย์สินของเจ้าของสิทธิ์แต่ละราย เว้นแต่จะระบุไว้เป็นอย่างอื่น',
        'คุณต้องไม่คัดลอก เผยแพร่ซ้ำ หรือใช้เนื้อหาของบริการเพื่อประโยชน์ทางการค้า ยกเว้นที่กฎหมายอนุญาตหรือได้รับอนุญาตเป็นลายลักษณ์อักษร',
      ],
    ),
    LegalSection(
      heading: '7. ข้อจำกัดความรับรอง',
      paragraphs: [
        'บริการนี้ให้ใช้งานตามสภาพและตามความพร้อม โดยไม่รับรองว่าจะเข้าถึงได้อย่างต่อเนื่อง ถูกต้องครบถ้วน หรือเหมาะสมกับวัตถุประสงค์เฉพาะใด',
        'โปรดอย่าใช้แอปเป็นแหล่งข้อมูลเพียงแหล่งเดียวสำหรับการตัดสินใจเร่งด่วนด้านความปลอดภัย การเดินทาง หรือสิ่งแวดล้อม',
      ],
    ),
    LegalSection(
      heading: '8. ข้อจำกัดความรับผิด',
      paragraphs: [
        'เท่าที่กฎหมายที่เกี่ยวข้องอนุญาต มหาวิทยาลัย ทีมโครงการ และผู้ให้บริการไม่รับผิดชอบต่อความเสียหายทางอ้อม อุบัติเหตุ พิเศษ หรือความเสียหายต่อเนื่องที่เกิดจากการใช้งานแอปหรือการไม่พร้อมให้บริการ',
      ],
    ),
    LegalSection(
      heading: '9. การเปลี่ยนแปลงข้อกำหนด',
      paragraphs: [
        'ข้อกำหนดเหล่านี้อาจได้รับการปรับปรุงเป็นครั้งคราว การใช้งานแอปต่อไปหลังจากมีการปรับปรุงหมายความว่าคุณยอมรับข้อกำหนดฉบับแก้ไข',
      ],
    ),
    LegalSection(
      heading: '10. ติดต่อ',
      paragraphs: [
        'หากมีคำถามเกี่ยวกับข้อกำหนดนี้ โปรดติดต่อผู้ดูแลโครงการ SUT Smart Bus หรือช่องทางสนับสนุนของมหาวิทยาลัยที่รับผิดชอบ',
      ],
    ),
  ],
);

const _termsEn = LegalDocumentContent(
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

const _privacyTh = LegalDocumentContent(
  title: 'นโยบายความเป็นส่วนตัว',
  effectiveDate: 'April 28, 2026',
  sections: [
    LegalSection(
      heading: '1. ขอบเขต',
      paragraphs: [
        'นโยบายความเป็นส่วนตัวนี้อธิบายว่า SUT Smart Bus อาจเก็บรวบรวม ใช้ จัดเก็บ และปกป้องข้อมูลอย่างไรเมื่อคุณใช้งานแอปพลิเคชันมือถือและบริการที่เกี่ยวข้อง',
      ],
    ),
    LegalSection(
      heading: '2. ข้อมูลที่อาจเก็บรวบรวม',
      paragraphs: [
        'แอปอาจประมวลผลตัวระบุอุปกรณ์ การตั้งค่าแอป ค่าภาษาและธีม การตั้งค่าการแจ้งเตือน ข้อมูลดีบักหรือวินิจฉัย และข้อมูลการโต้ตอบกับบริการ',
        'หากคุณเปิดใช้ฟีเจอร์ที่เกี่ยวข้องกับตำแหน่ง แอปอาจประมวลผลตำแหน่งอุปกรณ์ของคุณเพื่อรองรับแผนที่ ข้อมูลรถบัสใกล้เคียง และฟังก์ชันที่เกี่ยวข้องกับเส้นทาง',
        'บริการอาจแสดงข้อมูลการดำเนินงานจากรถบัสและเซ็นเซอร์ เช่น ตำแหน่ง GPS จำนวนผู้โดยสาร และค่าตรวจวัดคุณภาพอากาศ',
      ],
    ),
    LegalSection(
      heading: '3. วิธีใช้ข้อมูล',
      paragraphs: [
        'เราใช้ข้อมูลเพื่อให้แอปทำงาน แสดงข้อมูลรถบัสและสิ่งแวดล้อม รักษาความน่าเชื่อถือของบริการ ตรวจสอบปัญหาทางเทคนิค และปรับปรุงประสบการณ์การเดินทางภายในมหาวิทยาลัย',
        'ข้อเสนอแนะหรือคำขอสนับสนุนอาจถูกใช้เพื่อตอบกลับรายงาน ตรวจสอบเหตุการณ์ และปรับปรุงรุ่นถัดไป',
      ],
    ),
    LegalSection(
      heading: '4. การแบ่งปันข้อมูล',
      paragraphs: [
        'ข้อมูลอาจถูกแบ่งปันกับบุคลากรมหาวิทยาลัยที่ได้รับอนุญาต ผู้ให้บริการเดินรถ ผู้ให้บริการโครงสร้างพื้นฐาน หรือผู้ดูแลโครงการเท่าที่จำเป็นต่อการให้บริการ รักษาความปลอดภัย บำรุงรักษา หรือปรับปรุงบริการ',
        'เราไม่ขายข้อมูลส่วนบุคคลผ่านแอปนี้',
      ],
    ),
    LegalSection(
      heading: '5. ระยะเวลาการเก็บรักษาข้อมูล',
      paragraphs: [
        'ข้อมูลจะถูกเก็บรักษาเท่าที่จำเป็นอย่างสมเหตุสมผลสำหรับการดำเนินงาน การวิเคราะห์ การแก้ไขปัญหา การวิจัย การปฏิบัติตามข้อกำหนด หรือความปลอดภัย',
        'ระยะเวลาการเก็บรักษาอาจแตกต่างกันตามประเภทข้อมูลและความจำเป็นของบริการ',
      ],
    ),
    LegalSection(
      heading: '6. ความปลอดภัย',
      paragraphs: [
        'เราอาจใช้มาตรการด้านการบริหารและเทคนิคที่เหมาะสมเพื่อปกป้องข้อมูลของบริการ แต่ไม่มีระบบใดรับประกันความปลอดภัยได้อย่างสมบูรณ์',
      ],
    ),
    LegalSection(
      heading: '7. ทางเลือกของคุณ',
      paragraphs: [
        'คุณสามารถจัดการค่าบางอย่างในเครื่อง เช่น ธีม ภาษา และการแจ้งเตือน ได้จากหน้าการตั้งค่าของแอป',
        'หากคุณไม่ยอมรับนโยบายนี้ คุณไม่ควรใช้งานแอป',
      ],
    ),
    LegalSection(
      heading: '8. เด็กและการใช้งานข้อมูลอ่อนไหว',
      paragraphs: [
        'แอปนี้มีไว้สำหรับชุมชนการเดินทางของมหาวิทยาลัย และไม่ได้ออกแบบให้เป็นแพลตฟอร์มสำหรับเด็กในการส่งข้อมูลส่วนบุคคลด้วยตนเอง',
        'ผู้ใช้ควรหลีกเลี่ยงการส่งข้อมูลส่วนบุคคล ข้อมูลการเงิน ข้อมูลสุขภาพ หรือข้อมูลลับผ่านฟีเจอร์ข้อเสนอแนะ',
      ],
    ),
    LegalSection(
      heading: '9. การปรับปรุงนโยบาย',
      paragraphs: [
        'นโยบายนี้อาจได้รับการปรับปรุงเพื่อให้สอดคล้องกับการเปลี่ยนแปลงด้านบริการ กฎหมาย ความปลอดภัย หรือการดำเนินงาน การใช้งานต่อไปหลังการปรับปรุงหมายความว่าคุณยอมรับนโยบายฉบับแก้ไข',
      ],
    ),
    LegalSection(
      heading: '10. ติดต่อ',
      paragraphs: [
        'หากมีคำถามหรือคำขอเกี่ยวกับความเป็นส่วนตัว โปรดติดต่อผู้ดูแลโครงการ SUT Smart Bus หรือช่องทางสนับสนุนของมหาวิทยาลัยที่รับผิดชอบ',
      ],
    ),
  ],
);

const _privacyEn = LegalDocumentContent(
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
