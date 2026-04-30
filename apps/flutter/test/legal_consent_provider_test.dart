import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sut_smart_bus/providers/legal_consent_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LegalConsentNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('loads as not accepted by default', () async {
      final notifier = LegalConsentNotifier();
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.hasAccepted, isFalse);
    });

    test('persists acceptance', () async {
      final notifier = LegalConsentNotifier();
      await Future<void>.delayed(Duration.zero);

      await notifier.accept();

      expect(notifier.state.hasAccepted, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('legal_consent_accepted_v1'), isTrue);
    });

    test('decline clears stored acceptance', () async {
      SharedPreferences.setMockInitialValues({
        'legal_consent_accepted_v1': true,
      });

      final notifier = LegalConsentNotifier();
      await Future<void>.delayed(Duration.zero);

      await notifier.decline();

      expect(notifier.state.hasAccepted, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('legal_consent_accepted_v1'), isNull);
    });
  });
}
