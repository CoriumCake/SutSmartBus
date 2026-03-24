import 'package:flutter/material.dart';

class AirQualityStatus {
  final String label;
  final Color color;
  final Color solidColor;

  const AirQualityStatus({
    required this.label,
    required this.color,
    required this.solidColor,
  });
}

AirQualityStatus getAirQualityStatus(double? value) {
  if (value == null) {
    return const AirQualityStatus(
      label: 'No Data', color: Colors.grey, solidColor: Colors.grey,
    );
  }
  if (value <= 25) {
    return AirQualityStatus(
      label: 'Good',
      color: Colors.green.withValues(alpha: 0.4),
      solidColor: Colors.green,
    );
  }
  if (value <= 50) {
    return AirQualityStatus(
      label: 'Moderate',
      color: Colors.yellow.withValues(alpha: 0.4),
      solidColor: const Color(0xFFCCCC00),
    );
  }
  if (value <= 75) {
    return AirQualityStatus(
      label: 'Unhealthy (Sensitive)',
      color: Colors.orange.withValues(alpha: 0.4),
      solidColor: Colors.orange,
    );
  }
  return AirQualityStatus(
    label: 'Unhealthy',
    color: Colors.red.withValues(alpha: 0.4),
    solidColor: Colors.red,
  );
}

Color getPMColor(double pm25) {
  if (pm25 <= 12) return const Color(0xFF4CAF50);   // Green
  if (pm25 <= 35) return const Color(0xFFFFEB3B);   // Yellow
  if (pm25 <= 55) return const Color(0xFFFF9800);   // Orange
  if (pm25 <= 150) return const Color(0xFFF44336);  // Red
  return const Color(0xFF9C27B0);                     // Purple
}
