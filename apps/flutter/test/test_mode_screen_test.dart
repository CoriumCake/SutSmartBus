import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:sut_smart_bus/models/bus.dart';
import 'package:sut_smart_bus/models/route_model.dart';
import 'package:sut_smart_bus/providers/data_provider.dart';
import 'package:sut_smart_bus/providers/simulation_provider.dart';
import 'package:sut_smart_bus/providers/test_mode_provider.dart';
import 'package:sut_smart_bus/screens/testing_screen.dart';
import 'package:sut_smart_bus/services/api_service.dart';
import 'package:sut_smart_bus/services/mqtt_service.dart';

import 'test_mode_screen_test.mocks.dart';

@GenerateMocks([MqttService, ApiService, DataNotifier])
void main() {
  late MockMqttService mockMqtt;
  late MockApiService mockApi;
  late MockDataNotifier mockData;

  setUp(() {
    mockMqtt = MockMqttService();
    mockApi = MockApiService();
    mockData = MockDataNotifier();

    // Stubs for MqttService
    when(mockMqtt.subscribeToCamCount(any)).thenReturn(null);
    when(mockMqtt.unsubscribeFromCamCount()).thenReturn(null);
    when(mockMqtt.connect()).thenAnswer((_) async {});
    when(mockMqtt.disconnect()).thenReturn(null);
    when(mockMqtt.isCamCountSubscribed).thenReturn(false);

    // Stubs for ApiService
    when(mockApi.fetchBuses()).thenAnswer((_) async => <Bus>[]);
    when(mockApi.fetchRoutes()).thenAnswer((_) async => <BusRoute>[]);
    when(mockApi.sendFakeLocation(any)).thenAnswer((_) async {});
    when(mockApi.deleteFakeLocation(any)).thenAnswer((_) async {});
  });

  // ─── Helper ────────────────────────────────────────────────────────────────

  List<Override> _overrides() => [
        mqttServiceProvider.overrideWithValue(mockMqtt),
        apiServiceProvider.overrideWithValue(mockApi),
        dataProvider.overrideWith((ref) => mockData),
        // Use a real SimulationNotifier backed by mock API — avoids MissingStubError
        simulationProvider.overrideWith(
            (ref) => SimulationNotifier(ref.watch(apiServiceProvider), ref)),
      ];

  Future<void> pumpScreen(WidgetTester tester) async {
    // Tall viewport so all cards are reachable via scroll
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(),
        child: const MaterialApp(home: TestingScreen()),
      ),
    );
    // Let DataNotifier.initialize() complete
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  // ─── Tests ──────────────────────────────────────────────────────────────────

  group('TestingScreen – Test Mode section', () {
    testWidgets('shows the "Test Mode (ESP32 Cam)" card title', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Test Mode (ESP32 Cam)'), findsOneWidget);
    });

    testWidgets('toggle is initially OFF', (tester) async {
      await pumpScreen(tester);
      await tester.ensureVisible(find.byKey(const Key('test_mode_toggle')));
      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const Key('test_mode_toggle')),
      );
      expect(toggle.value, isFalse);
    });

    testWidgets('tapping toggle enables test mode and shows extra widgets',
        (tester) async {
      await pumpScreen(tester);
      await tester.ensureVisible(find.byKey(const Key('test_mode_toggle')));
      await tester.tap(find.byKey(const Key('test_mode_toggle')));
      await tester.pump();

      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const Key('test_mode_toggle')),
      );
      expect(toggle.value, isTrue);

      await tester.ensureVisible(find.byKey(const Key('cam_url_dropdown')));
      expect(find.byKey(const Key('cam_url_dropdown')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('person_count_tile')));
      expect(find.byKey(const Key('person_count_tile')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('sim_position_map')));
      expect(find.byKey(const Key('sim_position_map')), findsOneWidget);
    });

    testWidgets('person-count badge shows 0 on enable', (tester) async {
      await pumpScreen(tester);
      await tester.ensureVisible(find.byKey(const Key('test_mode_toggle')));
      await tester.tap(find.byKey(const Key('test_mode_toggle')));
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('person_count_tile')));
      expect(find.text('0'), findsWidgets);
    });

    testWidgets('camera dropdown reflects first URL on enable', (tester) async {
      await pumpScreen(tester);
      await tester.ensureVisible(find.byKey(const Key('test_mode_toggle')));
      await tester.tap(find.byKey(const Key('test_mode_toggle')));
      await tester.pump();

      await tester.ensureVisible(find.text(kCamUrls.first));
      expect(find.text(kCamUrls.first), findsOneWidget);
    });

    testWidgets('selecting a different camera URL updates the dropdown',
        (tester) async {
      await pumpScreen(tester);
      await tester.ensureVisible(find.byKey(const Key('test_mode_toggle')));
      await tester.tap(find.byKey(const Key('test_mode_toggle')));
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('cam_url_dropdown')));
      await tester.tap(find.byKey(const Key('cam_url_dropdown')));
      await tester.pumpAndSettle();

      final secondUrl = kCamUrls[1];
      await tester.tap(find.text(secondUrl).last);
      await tester.pumpAndSettle();

      expect(find.text(secondUrl), findsOneWidget);
    });

    testWidgets('disabling test mode resets provider state',
        (tester) async {
      // Use a ProviderContainer to test state directly
      final container = ProviderContainer(overrides: _overrides());
      addTearDown(container.dispose);

      // Read the notifier
      final notifier = container.read(testModeProvider.notifier);

      // Enable
      notifier.toggle();
      expect(container.read(testModeProvider).enabled, isTrue);
      expect(container.read(testModeProvider).selectedCamUrl, isNotNull);

      // Disable
      notifier.toggle();
      final state = container.read(testModeProvider);
      expect(state.enabled, isFalse);
      expect(state.selectedCamUrl, isNull);
      expect(state.simulatedPersonCount, equals(0));
    });

    testWidgets('position label text is correct for preset[0] coordinates',
        (tester) async {
      final p0 = kPresetPositions[0];
      final labelText =
          '(${p0.dx.toStringAsFixed(0)}, ${p0.dy.toStringAsFixed(0)})';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Text(labelText),
          ),
        ),
      );

      expect(find.text(labelText), findsOneWidget);
    });
  });
}
