import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

final userLocationProvider = StreamProvider<Position?>((ref) async* {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    yield null;
    return;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    yield null;
    return;
  }

  try {
    final lastKnownPosition = await Geolocator.getLastKnownPosition();
    if (lastKnownPosition != null) {
      yield lastKnownPosition;
    }
  } catch (_) {}

  try {
    yield await Geolocator.getCurrentPosition();
  } catch (_) {}

  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 5,
    ),
  );
});
