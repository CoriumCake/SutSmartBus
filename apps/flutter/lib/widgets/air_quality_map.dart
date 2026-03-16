import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/bus.dart';
import '../providers/data_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/air_quality_utils.dart';
import '../utils/map_styles.dart';

class AirQualityMapWidget extends ConsumerStatefulWidget {
  final List<Bus> buses;
  final String timeRange;
  final ValueChanged<String> onTimeRangeChanged;

  const AirQualityMapWidget({
    super.key,
    required this.buses,
    required this.timeRange,
    required this.onTimeRangeChanged,
  });

  @override
  ConsumerState<AirQualityMapWidget> createState() => _AirQualityMapWidgetState();
}

class _AirQualityMapWidgetState extends ConsumerState<AirQualityMapWidget> {
  GoogleMapController? _mapController;
  Set<Polygon> _polygons = {};
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
    }
  }

  Future<void> _fetchHeatmapData() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final rawData = await api.fetchHeatmapData(timeRange: widget.timeRange);
      _buildHeatmap(rawData);
    } catch (e) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      final lat = point['lat'] as double?;
      final lon = point['lon'] as double?;
      final pm25 = point['pm2_5'] as double?;
      if (lat != null && lon != null && pm25 != null) {
        addPoint(lat, lon, pm25);
      }
    }

    // Add live bus data
    for (final bus in widget.buses) {
      if (bus.currentLat != null && bus.currentLon != null && bus.pm25 != null) {
        addPoint(bus.currentLat!, bus.currentLon!, bus.pm25!);
      }
    }

    final newPolygons = <Polygon>{};

    grid.forEach((key, values) {
      final parts = key.split(',');
      final lat = double.parse(parts[0]);
      final lon = double.parse(parts[1]);
      final avgPm25 = values.reduce((a, b) => a + b) / values.length;

      final color = getPMColor(avgPm25).withOpacity(0.4);

      newPolygons.add(
        Polygon(
          polygonId: PolygonId(key),
          points: [
            LatLng(lat - _gridSize / 2, lon - _gridSize / 2),
            LatLng(lat + _gridSize / 2, lon - _gridSize / 2),
            LatLng(lat + _gridSize / 2, lon + _gridSize / 2),
            LatLng(lat - _gridSize / 2, lon + _gridSize / 2),
          ],
          fillColor: color,
          strokeWidth: 0,
        ),
      );
    });

    setState(() => _polygons = newPolygons);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider).isDark;

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: const CameraPosition(
            target: _sutCenter,
            zoom: 14.5,
          ),
          onMapCreated: (controller) => _mapController = controller,
          polygons: _polygons,
          style: isDark ? darkMapStyleJson : null,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
        ),

        // Time filter buttons
        Positioned(
          top: 10,
          right: 10,
          child: Card(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFilterButton('1h'),
                _buildFilterButton('24h'),
              ],
            ),
          ),
        ),

        if (_loading)
          const Positioned(
            top: 20,
            left: 20,
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }

  Widget _buildFilterButton(String range) {
    final isSelected = widget.timeRange == range;
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => widget.onTimeRangeChanged(range),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          range,
          style: TextStyle(
            color: isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}
