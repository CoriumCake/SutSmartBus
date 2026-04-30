import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../models/bus.dart';
import '../models/route_model.dart';

class ApiService {
  late final Dio _dio;

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      headers: ApiConfig.headers,
    ));
  }

  // ─── Buses ───────────────────────────────────────

  Future<List<Bus>> fetchBuses() async {
    try {
      final response = await _dio.get('/api/buses');
      if (response.data is List) {
        return (response.data as List).map((j) => Bus.fromJson(j)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[ApiService] Error fetching buses: $e');
      return [];
    }
  }

  Future<int?> fetchPassengerCount() async {
    try {
      // Server uses /api/passengers/latest which returns a list of latest counts per bus
      final response = await _dio.get('/api/passengers/latest');
      if (response.data is List && (response.data as List).isNotEmpty) {
        // Return sum of all passengers or just the first one if specific logic is needed
        int total = 0;
        for (var item in response.data) {
          total += (item['count'] as int? ?? 0);
        }
        return total;
      }
      return 0;
    } catch (e) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchPassengerCountHistory({
    int hours = 24,
  }) async {
    try {
      final response = await _dio.get(
        '/api/analytics/passenger-count-history',
        queryParameters: {'hours': hours},
      );
      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      debugPrint('[ApiService] Error fetching passenger history: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> fetchPassengerStats({
    String period = 'daily',
  }) async {
    try {
      final response = await _dio.get(
        '/api/analytics/passenger-stats',
        queryParameters: {'period': period},
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('[ApiService] Error fetching passenger stats: $e');
      return null;
    }
  }

  // ─── Routes ──────────────────────────────────────

  Future<List<BusRoute>> fetchRoutes() async {
    try {
      // 1. Fetch all routes
      final routesRes = await _dio.get('/api/routes');
      // 2. Fetch all stops (server doesn't have route-specific stops endpoint yet)
      final stopsRes = await _dio.get('/api/stops');

      final allStops = (stopsRes.data as List?)
              ?.map((s) => {
                    'latitude': s['lat'],
                    'longitude': s['lon'],
                    'stopName': s['name'],
                    'isStop': true,
                  })
              .toList() ??
          [];

      if (routesRes.data is List) {
        return (routesRes.data as List).map((r) {
          // In this server version, we might need to filter stops by route
          // For now, we'll attach all stops or handle via mapping if available
          return BusRoute.fromJson({
            ...r as Map<String, dynamic>,
            'waypoints': allStops,
          });
        }).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[ApiService] Error fetching routes: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchRouteList() async {
    try {
      // Server uses /api/bus-route-mapping for the list and metadata
      final response = await _dio.get('/api/bus-route-mapping');
      return List<Map<String, dynamic>>.from(response.data['routes'] ?? []);
    } catch (e) {
      return [];
    }
  }

  Future<BusRoute?> fetchRoute(String routeId) async {
    try {
      // Server might not have direct route by ID if using static files
      // But we can try the general routes list
      final response = await _dio.get('/api/routes');
      if (response.data is List) {
        final routeJson = (response.data as List).firstWhere(
          (r) => r['id'].toString() == routeId,
          orElse: () => null,
        );
        if (routeJson != null) return BusRoute.fromJson(routeJson);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> syncRoute(BusRoute route) async {
    try {
      final response = await _dio.post('/api/routes', data: route.toJson());
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteRoute(String routeId) async {
    try {
      await _dio.delete('/api/routes/$routeId');
      return true;
    } catch (e) {
      return false;
    }
  }

  // ─── Bus Management ──────────────────────────────

  Future<bool> createBus(String mac, String name) async {
    try {
      await _dio.post('/api/buses', data: {
        'mac_address': mac,
        'bus_name': name,
        'current_lat': 0.0,
        'current_lon': 0.0,
        'seats_available': 0,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateBus(String mac, String name) async {
    try {
      await _dio.put('/api/buses/$mac', data: {'bus_name': name});
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteBus(String mac) async {
    try {
      await _dio.delete('/api/buses/$mac');
      return true;
    } catch (e) {
      return false;
    }
  }

  // ─── Bus Route Mapping ───────────────────────────

  Future<Map<String, dynamic>?> fetchBusRouteMappings(int localVersion) async {
    try {
      final response = await _dio.get('/api/bus-route-mapping');
      return response.data;
    } catch (e) {
      return null;
    }
  }

  // ─── Air Quality ─────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchHeatmapData(
      {String timeRange = '1h'}) async {
    try {
      // Map '1h', '24h' etc to hours integer
      int hours = 1;
      if (timeRange.endsWith('h')) {
        hours = int.tryParse(timeRange.replaceAll('h', '')) ?? 1;
      } else if (timeRange.endsWith('d')) {
        hours = (int.tryParse(timeRange.replaceAll('d', '')) ?? 1) * 24;
      }

      final response = await _dio
          .get('/api/analytics/heatmap', queryParameters: {'hours': hours});
      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<void> sendFakeLocation(Map<String, dynamic> data) async {
    try {
      await _dio.post('/api/debug/location', data: data);
    } catch (e) {
      // Silent
    }
  }

  Future<void> deleteFakeLocation(String busId) async {
    try {
      await _dio.delete('/api/debug/location/$busId');
    } catch (e) {
      // Silent
    }
  }

  // ─── PM Zones ────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPMZones() async {
    try {
      final response = await _dio.get('/api/pm_zones');
      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> createPMZone(Map<String, dynamic> zoneData) async {
    try {
      final response = await _dio.post('/api/pm_zones', data: zoneData);
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updatePMZone(
      String zoneId, Map<String, dynamic> zoneData) async {
    try {
      final response = await _dio.put('/api/pm_zones/\$zoneId', data: zoneData);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deletePMZone(String zoneId) async {
    try {
      await _dio.delete('/api/pm_zones/\$zoneId');
      return true;
    } catch (e) {
      return false;
    }
  }

  // ─── Feedback ────────────────────────────────────

  Future<bool> submitFeedback(String name, String message) async {
    try {
      final response = await _dio.post('/api/feedback', data: {
        'name': name,
        'message': message,
      });
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('[ApiService] Error submitting feedback: \$e');
      return false;
    }
  }

  // ─── Health & System ─────────────────────────────

  Future<Map<String, dynamic>?> fetchSystemInfo() async {
    try {
      final response = await _dio.get('/api/system-info');
      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get('/health');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
