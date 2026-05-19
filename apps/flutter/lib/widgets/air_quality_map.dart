import 'dart:async';
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
  final String timeRange;
  final ValueChanged<String> onTimeRangeChanged;
  final bool keepControlsInSafeArea;

  const AirQualityMapWidget({
    super.key,
    required this.buses,
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
    } else if (oldWidget.buses != widget.buses) {
      _buildHeatmap(_rawHeatmapData);
    }
  }

  Future<void> _fetchHeatmapData() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final rawData = await api.fetchHeatmapData(timeRange: widget.timeRange);
      _rawHeatmapData = rawData;
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

  void _buildHeatmap(List<Map<String, dynamic>> rawData) {
    // Snap to grid
    final grid = <String, List<double>>{};

    double snap(double val) => (val / _gridSize).round() * _gridSize;

    void addPoint(double lat, double lon, double pm25) {
      final key = '${snap(lat)},${snap(lon)}';
      grid.putIfAbsent(key, () => []).add(pm25);
    }

    // Add API data
    for (final point in rawData) {
      final lat = point['latitude'] as double? ?? point['lat'] as double?;
      final lon = point['longitude'] as double? ?? point['lon'] as double?;
      final pm25 = point['weight'] as double? ?? point['pm2_5'] as double?;
      if (lat != null && lon != null && pm25 != null) {
        addPoint(lat, lon, pm25);
      }
    }

    // Add live bus data
    for (final bus in widget.buses) {
      if (bus.currentLat != null &&
          bus.currentLon != null &&
          bus.pm25 != null) {
        addPoint(bus.currentLat!, bus.currentLon!, bus.pm25!);
      }
    }

    final newPolygons = <Polygon>[];

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
