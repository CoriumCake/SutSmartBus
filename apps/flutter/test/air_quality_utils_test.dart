import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sut_smart_bus/utils/air_quality_utils.dart';

void main() {
  group('air quality colors', () {
    test('uses the same PM2.5 bands for heatmap colors and card status', () {
      for (final pm25 in [10.0, 20.0, 30.0, 60.0, 90.0]) {
        expect(getPMColor(pm25), getAirQualityStatus(pm25).solidColor);
      }
    });

    test('keeps 20 PM2.5 in the Good/green band', () {
      expect(getAirQualityStatus(20).label, 'Good');
      expect(getPMColor(20), Colors.green);
    });
  });
}
