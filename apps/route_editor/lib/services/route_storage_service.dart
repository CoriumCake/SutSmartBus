import 'dart:convert';
import 'package:hive/hive.dart';
import '../models/route_model.dart';

class RouteStorageService {
  static const _boxName = 'route_editor_routes';

  Future<Box> _openBox() => Hive.openBox(_boxName);

  Future<void> saveRoute(BusRoute route) async {
    final box = await _openBox();
    await box.put(route.routeId, jsonEncode(route.toJson()));
  }

  Future<BusRoute?> loadRoute(String routeId) async {
    final box = await _openBox();
    final json = box.get(routeId);
    if (json == null) return null;
    return BusRoute.fromJson(jsonDecode(json));
  }

  Future<List<BusRoute>> getAllRoutes() async {
    final box = await _openBox();
    return box.values
        .map((json) => BusRoute.fromJson(jsonDecode(json)))
        .toList();
  }

  Future<void> deleteRoute(String routeId) async {
    final box = await _openBox();
    await box.delete(routeId);
  }

  Future<void> replaceAll(List<BusRoute> routes) async {
    final box = await _openBox();
    await box.clear();
    for (final route in routes) {
      await box.put(route.routeId, jsonEncode(route.toJson()));
    }
  }
}
