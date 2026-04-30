import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _legalConsentKey = 'legal_consent_accepted_v1';

class LegalConsentState {
  final bool isLoading;
  final bool hasAccepted;

  const LegalConsentState({
    required this.isLoading,
    required this.hasAccepted,
  });

  const LegalConsentState.loading()
      : isLoading = true,
        hasAccepted = false;

  const LegalConsentState.ready({required bool hasAccepted})
      : isLoading = false,
        hasAccepted = hasAccepted;
}

class LegalConsentNotifier extends StateNotifier<LegalConsentState> {
  LegalConsentNotifier() : super(const LegalConsentState.loading()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = LegalConsentState.ready(
      hasAccepted: prefs.getBool(_legalConsentKey) ?? false,
    );
  }

  Future<void> accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_legalConsentKey, true);
    state = const LegalConsentState.ready(hasAccepted: true);
  }

  Future<void> decline() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legalConsentKey);
    state = const LegalConsentState.ready(hasAccepted: false);
  }
}

final legalConsentProvider =
    StateNotifierProvider<LegalConsentNotifier, LegalConsentState>((ref) {
  return LegalConsentNotifier();
});
