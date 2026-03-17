import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class BusMappingService {
  static const _key = 'bus_route_mappings';

  Future<Map<String, String>> getAllMappings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr == null) return {};
    try {
      final Map<String, dynamic> decoded = jsonDecode(jsonStr);
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      return {};
    }
  }

  Future<void> saveMapping(String busMac, String routeId) async {
    final prefs = await SharedPreferences.getInstance();
    final mappings = await getAllMappings();
    mappings[busMac] = routeId;
    await prefs.setString(_key, jsonEncode(mappings));
  }

  Future<void> removeMapping(String busMac) async {
    final prefs = await SharedPreferences.getInstance();
    final mappings = await getAllMappings();
    mappings.remove(busMac);
    await prefs.setString(_key, jsonEncode(mappings));
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
