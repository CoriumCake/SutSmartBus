import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../models/route_model.dart';

class ApiService {
  late final Dio _dio;

  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        headers: ApiConfig.headers,
      ),
    );
  }

  Future<List<BusRoute>> fetchRoutes() async {
    try {
      final mappingRes = await _dio.get('/api/bus-route-mapping');
      final mappedRouteEntries =
          (mappingRes.data['routes'] as List?)
              ?.map((route) => Map<String, dynamic>.from(route as Map))
              .toList() ??
          [];
      final mappedRoutes = <BusRoute>[];

      for (final routeEntry in mappedRouteEntries) {
        final filename = routeEntry['file']?.toString();
        if (filename == null || filename.isEmpty) continue;

        try {
          final routeFileRes = await _dio.get('/api/route-file/$filename');
          if (routeFileRes.data is Map<String, dynamic>) {
            mappedRoutes.add(
              BusRoute.fromJson({
                ...(routeFileRes.data as Map<String, dynamic>),
                'route_id': routeEntry['route_id'],
                'route_name': routeEntry['route_name'],
                'route_color': routeEntry['route_color'],
              }),
            );
          }
        } catch (e) {
          debugPrint(
            '[RouteEditorApi] Error fetching route file $filename: $e',
          );
        }
      }

      return mappedRoutes;
    } catch (e) {
      debugPrint('[RouteEditorApi] Error fetching routes: $e');
      return [];
    }
  }

  Future<bool> syncRoute(BusRoute route) async {
    try {
      final response = await _dio.post('/api/routes', data: route.toJson());
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('[RouteEditorApi] Error syncing route ${route.routeId}: $e');
      return false;
    }
  }

  Future<bool> deleteRoute(String routeId) async {
    try {
      final response = await _dio.delete('/api/routes/$routeId');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[RouteEditorApi] Error deleting route $routeId: $e');
      return false;
    }
  }
}
