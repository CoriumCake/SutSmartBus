import 'dart:math';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

class RideSession {
  final String sessionId;
  final String busMac;
  final String status;
  final DateTime startedAt;
  final DateTime expiresAt;

  const RideSession({
    required this.sessionId,
    required this.busMac,
    required this.status,
    required this.startedAt,
    required this.expiresAt,
  });

  factory RideSession.fromJson(Map<String, dynamic> json) {
    return RideSession(
      sessionId: json['session_id'] as String,
      busMac: json['bus_mac'] as String,
      status: json['status'] as String? ?? 'active',
      startedAt: DateTime.parse(json['started_at'] as String).toLocal(),
      expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
    );
  }
}

class RideStatus {
  final bool active;
  final RideSession? session;

  const RideStatus({
    required this.active,
    required this.session,
  });
}

class BusService {
  static const _installIdKey = 'bus_install_id';
  final Dio _dio;

  BusService()
      : _dio = Dio(
          BaseOptions(
            baseUrl: ApiConfig.baseUrl,
            connectTimeout: const Duration(seconds: 4),
            receiveTimeout: const Duration(seconds: 4),
            sendTimeout: const Duration(seconds: 4),
          ),
        );

  Future<String> _getInstallId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_installIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final id = List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    await prefs.setString(_installIdKey, id);
    return id;
  }

  Future<RideSession> startRideSession({
    required String busMac,
    required double userLat,
    required double userLon,
  }) async {
    try {
      final response = await _dio.post(
        '/api/rides/start',
        data: {
          'bus_mac': busMac,
          'device_id': await _getInstallId(),
          'user_lat': userLat,
          'user_lon': userLon,
        },
        options: Options(headers: ApiConfig.headers),
      );
      final sessionJson = response.data['session'] as Map<String, dynamic>?;
      if (response.statusCode != 200 || sessionJson == null) {
        throw Exception('Ride session could not be created');
      }
      return RideSession.fromJson(sessionJson);
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['detail'] ?? e.message ?? 'Failed to start ride',
      );
    }
  }

  Future<void> endRideSession(String sessionId) async {
    try {
      await _dio.post(
        '/api/rides/end',
        data: {
          'session_id': sessionId,
          'device_id': await _getInstallId(),
        },
        options: Options(headers: ApiConfig.headers),
      );
    } on DioException {
      // Best effort only. Local ride state should still be cleared.
    }
  }

  Future<RideStatus> getRideStatus(String sessionId) async {
    final response = await _dio.post(
      '/api/rides/status',
      data: {
        'session_id': sessionId,
        'device_id': await _getInstallId(),
      },
      options: Options(headers: ApiConfig.headers),
    );

    final active = response.data['active'] == true;
    final sessionJson = response.data['session'] as Map<String, dynamic>?;
    return RideStatus(
      active: active,
      session: sessionJson == null ? null : RideSession.fromJson(sessionJson),
    );
  }

  Future<void> ringBell({
    required String busMac,
    required String sessionId,
    required double userLat,
    required double userLon,
  }) async {
    try {
      final response = await _dio.post(
        '/api/ring',
        data: {
          'bus_mac': busMac,
          'session_id': sessionId,
          'device_id': await _getInstallId(),
          'user_lat': userLat,
          'user_lon': userLon,
        },
        options: Options(headers: ApiConfig.headers),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to ring bell: ${response.statusCode}');
      }
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['detail'] ?? e.message ?? 'Failed to ring bell',
      );
    }
  }

  Future<bool> isBackendReachable() async {
    try {
      final response = await _dio.get(
        '/health',
        options: Options(
          headers: ApiConfig.headers,
          receiveTimeout: const Duration(seconds: 3),
        ),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
