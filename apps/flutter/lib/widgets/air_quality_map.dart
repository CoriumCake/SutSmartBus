import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/bus.dart';
import '../providers/data_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/air_quality_utils.dart';

class AirQualityMapWidget extends ConsumerStatefulWidget {
  final List<Bus> buses;
  final List<Bus>? heatmapBuses;
  final Set<String> excludedHeatmapBusMacs;
  final String timeRange;
  final ValueChanged<String> onTimeRangeChanged;
  final bool keepControlsInSafeArea;

  const AirQualityMapWidget({
    super.key,
    required this.buses,
    this.heatmapBuses,
    this.excludedHeatmapBusMacs = const <String>{},
    required this.timeRange,
    required this.onTimeRangeChanged,
    this.keepControlsInSafeArea = false,
  });

  @override
  ConsumerState<AirQualityMapWidget> createState() =>
      _AirQualityMapWidgetState();
}

class _AirQualityMapWidgetState extends ConsumerState<AirQualityMapWidget> {
  final MapController _mapController = MapController();
  List<Polygon> _polygons = [];
  List<Map<String, dynamic>> _rawHeatmapData = [];
  List<Map<String, dynamic>> _rawZoneData = [];
  bool _loading = false;

  static const _sutCenter = LatLng(14.8820, 102.0207);
  static const _gridSize = 0.001; // ~111m

  @override
  void initState() {
    super.initState();
    _fetchHeatmapData();
  }

  @override
  void didUpdateWidget(AirQualityMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeRange != widget.timeRange) {
      _fetchHeatmapData();
    } else if ((oldWidget.heatmapBuses ?? oldWidget.buses) !=
            (widget.heatmapBuses ?? widget.buses) ||
        oldWidget.excludedHeatmapBusMacs != widget.excludedHeatmapBusMacs) {
      _buildHeatmap(_rawHeatmapData);
    }
  }

  Future<void> _fetchHeatmapData() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final rawData = await api.fetchHeatmapData(timeRange: widget.timeRange);
      final zoneData = await api.fetchPMZones();
      _rawHeatmapData = rawData;
      _rawZoneData = zoneData;
      _buildHeatmap(rawData);
    } catch (e) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Marker> _buildBusMarkers() {
    return widget.buses
        .where((bus) => bus.currentLat != null && bus.currentLon != null)
        .map(
          (bus) => Marker(
            point: LatLng(bus.currentLat!, bus.currentLon!),
            width: 36,
            height: 36,
            child: Tooltip(
              message: bus.busName,
              child: Opacity(
                opacity: bus.isOffline ? 0.6 : 1.0,
                child: Image.asset(
                  'assets/images/bus_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        )
        .toList();
  }

  double? _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  double? _readDouble(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final parsed = _asDouble(source[key]);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  List<LatLng> _zonePoints(Map<String, dynamic> zone) {
    final rawPoints = zone['points'];
    if (rawPoints is List) {
      final points = <LatLng>[];
      for (final rawPoint in rawPoints) {
        double? lat;
        double? lon;
        if (rawPoint is List && rawPoint.length >= 2) {
          lat = _asDouble(rawPoint[0]);
          lon = _asDouble(rawPoint[1]);
        } else if (rawPoint is Map<String, dynamic>) {
          lat = _readDouble(rawPoint, ['lat', 'latitude']);
          lon = _readDouble(rawPoint, ['lon', 'longitude']);
        }
        if (lat != null && lon != null) {
          points.add(LatLng(lat, lon));
        }
      }
      if (points.length >= 3) {
        return points;
      }
    }

    final lat = _readDouble(zone, ['lat', 'latitude']);
    final lon = _readDouble(zone, ['lon', 'longitude']);
    if (lat == null || lon == null) {
      return const [];
    }

    final radiusM = _readDouble(zone, ['radius']) ?? 50.0;
    const metersPerDegree = 111320.0;
    final latRadius = radiusM / metersPerDegree;
    final lonRadius =
        radiusM / (metersPerDegree * math.cos(lat * math.pi / 180));

    return List.generate(24, (index) {
      final angle = (math.pi * 2 * index) / 24;
      return LatLng(
        lat + math.sin(angle) * latRadius,
        lon + math.cos(angle) * lonRadius,
      );
    });
  }

  List<Polygon> _buildZonePolygons() {
    final polygons = <Polygon>[];
    for (final zone in _rawZoneData) {
      final pm25 = _readDouble(zone, ['avg_pm25', 'avg_pm2_5', 'pm2_5']);
      if (pm25 == null || pm25 <= 0) {
        continue;
      }

      final points = _zonePoints(zone);
      if (points.length < 3) {
        continue;
      }

      final color = getPMColor(pm25);
      polygons.add(
        Polygon(
          points: points,
          color: color.withValues(alpha: 0.28),
          borderColor: color.withValues(alpha: 0.65),
          borderStrokeWidth: 1,
        ),
      );
    }
    return polygons;
  }

  void _buildHeatmap(List<Map<String, dynamic>> rawData) {
    // Snap to grid
    final grid = <String, List<double>>{};
    final liveHeatmapBuses = widget.heatmapBuses ?? widget.buses;

    double snap(double val) => (val / _gridSize).round() * _gridSize;

    void addPoint(double lat, double lon, double pm25) {
      final key = '${snap(lat)},${snap(lon)}';
      grid.putIfAbsent(key, () => []).add(pm25);
    }

    // Add API data
    for (final point in rawData) {
      final lat = _readDouble(point, ['latitude', 'lat']);
      final lon = _readDouble(point, ['longitude', 'lon']);
      final pm25 = _readDouble(point, ['weight', 'pm2_5']);
      if (lat != null && lon != null && pm25 != null) {
        addPoint(lat, lon, pm25);
      }
    }

    // Add live bus data
    for (final bus in liveHeatmapBuses) {
      if (widget.excludedHeatmapBusMacs.contains(bus.busMac)) {
        continue;
      }
      if (bus.currentLat != null &&
          bus.currentLon != null &&
          bus.pm25 != null) {
        addPoint(bus.currentLat!, bus.currentLon!, bus.pm25!);
      }
    }

    final newPolygons = _buildZonePolygons();

    grid.forEach((key, values) {
      final parts = key.split(',');
      final lat = double.parse(parts[0]);
      final lon = double.parse(parts[1]);
      final avgPm25 = values.reduce((a, b) => a + b) / values.length;

      final color = getPMColor(avgPm25).withValues(alpha: 0.5);

      newPolygons.add(
        Polygon(
          points: [
            LatLng(lat - _gridSize / 2, lon - _gridSize / 2),
            LatLng(lat + _gridSize / 2, lon - _gridSize / 2),
            LatLng(lat + _gridSize / 2, lon + _gridSize / 2),
            LatLng(lat - _gridSize / 2, lon + _gridSize / 2),
          ],
          color: color,
          borderStrokeWidth: 0,
        ),
      );
    });

    setState(() => _polygons = newPolygons);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider).isDark;
    final topControlInset =
        widget.keepControlsInSafeArea ? MediaQuery.paddingOf(context).top : 0.0;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: _sutCenter,
            initialZoom: 14.5,
          ),
          children: [
            TileLayer(
              urlTemplate: isDark
                  ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                  : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.catcode.sut_smart_bus',
            ),
            PolygonLayer(polygons: _polygons),
            MarkerLayer(markers: _buildBusMarkers()),
          ],
        ),

        // Modern filter selector
        Positioned(
          top: topControlInset + 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModernFilter('1h'),
                _buildModernFilter('24h'),
              ],
            ),
          ),
        ),

        if (_loading)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }

  Widget _buildModernFilter(String range) {
    final isSelected = widget.timeRange == range;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => widget.onTimeRangeChanged(range),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Text(
          range,
          style: TextStyle(
            color:
                isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
