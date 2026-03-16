import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationState {
  final bool enabled;

  NotificationState({this.enabled = true});
}

class NotificationNotifier extends StateNotifier<NotificationState> {
  NotificationNotifier() : super(NotificationState()) {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('notifications_enabled') ?? true;
    state = NotificationState(enabled: enabled);
  }

  Future<void> enable() async {
    state = NotificationState(enabled: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', true);
  }

  Future<void> disable() async {
    state = NotificationState(enabled: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', false);
  }
}

final notificationProvider = StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
  return NotificationNotifier();
});
