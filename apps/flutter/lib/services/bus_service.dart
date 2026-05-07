import 'package:dio/dio.dart';
import '../config/api_config.dart';

class RingRequest {
  final String busMac;

  RingRequest({required this.busMac});

  Map<String, dynamic> toJson() {
    return {
      'bus_mac': busMac,
    };
  }
}

class BusService {
  final Dio _dio;

  BusService() :
    _dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));

  Future<void> ringBell(String busMac) async {
    try {
      final response = await _dio.post(
        '/api/ring',
        data: RingRequest(busMac: busMac).toJson(),
        options: Options(
          headers: ApiConfig.headers,
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
