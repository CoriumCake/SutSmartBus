import 'package:flutter_test/flutter_test.dart';
import 'package:sut_smart_bus/models/bus.dart';

void main() {
  group('Bus.fromJson', () {
    test('keeps developer reset passenger count as zero', () {
      final bus = Bus.fromJson({
        'bus_id': 'SUT-BUS-01',
        'mac_address': 'BUS-01',
        'bus_name': 'Bus 01',
        'person_count': 0,
        'count_source': 'developer',
      });

      expect(bus.personCount, 0);
    });
  });
}
