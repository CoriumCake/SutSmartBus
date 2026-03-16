import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageState {
  final String language; // 'en' or 'th'
  final Map<String, String> translations;

  LanguageState({required this.language, required this.translations});

  String t(String key) => translations[key] ?? key;
}

class LanguageNotifier extends StateNotifier<LanguageState> {
  LanguageNotifier() : super(LanguageState(
    language: 'en',
    translations: _enTranslations,
  )) {
    _loadSavedLanguage();
  }

  Future<void> _loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString('app_language') ?? 'en';
    state = LanguageState(
      language: savedLang,
      translations: savedLang == 'th' ? _thTranslations : _enTranslations,
    );
  }

  Future<void> changeLanguage(String lang) async {
    state = LanguageState(
      language: lang,
      translations: lang == 'th' ? _thTranslations : _enTranslations,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', lang);
  }
}

final languageProvider = StateNotifierProvider<LanguageNotifier, LanguageState>((ref) {
  return LanguageNotifier();
});

// ─── Translations ───────────────────────────────────

const _enTranslations = {
  'routes': 'Routes',
  'settings': 'Settings',
  'darkMode': 'Dark Mode',
  'notifications': 'Notifications',
  'language': 'Language',
  'debugMode': 'Debug Mode',
  'about': 'About',
  'busManagement': 'Bus Management',
  'routeAdmin': 'Bus Route Admin',
  'airQuality': 'Air Quality',
  'version': 'Version',
  'appDescription': 'Smart transit & environmental monitoring for Suranaree University of Technology.',
  'noActiveBuses': 'No active buses',
  'refresh': 'Refresh',
  'selectLanguage': 'Select Language',
  // Add more as needed
};

const _thTranslations = {
  'routes': 'เส้นทาง',
  'settings': 'ตั้งค่า',
  'darkMode': 'โหมดมืด',
  'notifications': 'การแจ้งเตือน',
  'language': 'ภาษา',
  'debugMode': 'โหมดดีบัก',
  'about': 'เกี่ยวกับ',
  'busManagement': 'จัดการรถบัส',
  'routeAdmin': 'จัดการเส้นทาง',
  'airQuality': 'คุณภาพอากาศ',
  'version': 'เวอร์ชัน',
  'appDescription': 'ระบบขนส่งอัจฉริยะและตรวจสอบสิ่งแวดล้อมสำหรับมหาวิทยาลัยเทคโนโลยีสุรนารี',
  'noActiveBuses': 'ไม่มีรถบัสที่ใช้งาน',
  'refresh': 'รีเฟรช',
  'selectLanguage': 'เลือกภาษา',
};
