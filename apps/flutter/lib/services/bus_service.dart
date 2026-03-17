import 'package:dio/dio.dart';
import '../core/config.dart'; // Assuming config.dart contains API_BASE_URL and API_SECRET_KEY

class RingRequest {
  final String bus_mac;

  RingRequest({required this.bus_mac});

  Map<String, dynamic> toJson() {
    return {
      'bus_mac': bus_mac,
    };
  }
}

class BusService {
  final Dio _dio;
  final String _apiKey;

  BusService() :
    _dio = Dio(BaseOptions(baseUrl: AppConfig.API_BASE_URL)),
    _apiKey = AppConfig.API_SECRET_KEY;

  Future<void> ringBell(String busMac) async {
    try {
      final response = await _dio.post(
        '/api/ring',
        data: RingRequest(bus_mac: busMac).toJson(),
        options: Options(
          headers: {
            'X-API-Key': _apiKey,
          },
        ),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to ring bell: ${response.statusCode}');
      }
      // Assuming a successful response is 200 and doesn't need specific data parsing for this.
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception('Failed to ring bell: ${e.response?.data['detail'] ?? e.message}');
      } else {
        throw Exception('Failed to ring bell: ${e.message}');
      }
    } catch (e) {
      throw Exception('Failed to ring bell: $e');
    }
  }
}
