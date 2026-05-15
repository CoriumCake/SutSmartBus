import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/bus.dart';
import '../providers/data_provider.dart';
import '../providers/theme_provider.dart';

class WifiHeatmapMapWidget extends ConsumerStatefulWidget {
  final List<Bus> buses;
  final String timeRange;
  final ValueChanged<String> onTimeRangeChanged;
  final bool keepControlsInSafeArea;

  const WifiHeatmapMapWidget({
    super.key,
    required this.buses,
    required this.timeRange,
    required this.onTimeRangeChanged,
    this.keepControlsInSafeArea = false,
  });

  @override
  ConsumerState<WifiHeatmapMapWidget> createState() =>
      _WifiHeatmapMapWidgetState();
}

class _WifiHeatmapMapWidgetState extends ConsumerState<WifiHeatmapMapWidget> {
  final MapController _mapController = MapController();
  List<Polygon> _polygons = [];
  List<Map<String, dynamic>> _rawHeatmapData = [];
  bool _loading = false;

  static const _sutCenter = LatLng(14.8820, 102.0207);
  static const _gridSize = 0.001;

  @override
  void initState() {
    super.initState();
    _fetchHeatmapData();
  }

  @override
  void didUpdateWidget(WifiHeatmapMapWidget oldWidget) {
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
      final rawData =
          await api.fetchWifiHeatmapData(timeRange: widget.timeRange);
      _rawHeatmapData = rawData;
      _buildHeatmap(rawData);
    } catch (e) {
      // Keep the map usable even if history is unavailable.
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
            width: 38,
            height: 38,
            child: Tooltip(
              message:
                  '${bus.busName}\nWiFi: ${_wifiLabel(bus.rssi, bus.isOffline)}',
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _wifiColor(bus.rssi, bus.isOffline),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.directions_bus,
                      size: 21, color: Colors.white),
                ],
              ),
            ),
          ),
        )
        .toList();
  }

  void _buildHeatmap(List<Map<String, dynamic>> rawData) {
    final grid = <String, List<int>>{};

    double snap(double val) => (val / _gridSize).round() * _gridSize;

    void addPoint(double lat, double lon, int rssi) {
      final key = '${snap(lat)},${snap(lon)}';
      grid.putIfAbsent(key, () => []).add(rssi);
    }

    for (final point in rawData) {
      final lat = (point['latitude'] as num?)?.toDouble() ??
          (point['lat'] as num?)?.toDouble();
      final lon = (point['longitude'] as num?)?.toDouble() ??
          (point['lon'] as num?)?.toDouble();
      final rssi = (point['rssi'] as num?)?.toInt();
      if (lat != null && lon != null && rssi != null) {
        addPoint(lat, lon, rssi);
      }
    }

    for (final bus in widget.buses) {
      if (bus.currentLat == null || bus.currentLon == null) {
        continue;
      }
      addPoint(
        bus.currentLat!,
        bus.currentLon!,
        bus.isOffline ? -100 : (bus.rssi ?? -100),
      );
    }

    final newPolygons = <Polygon>[];

    grid.forEach((key, values) {
      final parts = key.split(',');
      final lat = double.parse(parts[0]);
      final lon = double.parse(parts[1]);
      final avgRssi = values.reduce((a, b) => a + b) / values.length;

      newPolygons.add(
        Polygon(
          points: [
            LatLng(lat - _gridSize / 2, lon - _gridSize / 2),
            LatLng(lat + _gridSize / 2, lon - _gridSize / 2),
            LatLng(lat + _gridSize / 2, lon + _gridSize / 2),
            LatLng(lat - _gridSize / 2, lon + _gridSize / 2),
          ],
          color: _wifiColor(avgRssi.round(), false).withValues(alpha: 0.55),
          borderStrokeWidth: 0,
        ),
      );
    });

    if (mounted) {
      setState(() => _polygons = newPolygons);
    }
  }

  Color _wifiColor(int? rssi, bool isOffline) {
    if (isOffline || rssi == null || rssi <= -90) {
      return Colors.red;
    }
    if (rssi >= -70) {
      return Colors.green;
    }
    return Colors.orange;
  }

  String _wifiLabel(int? rssi, bool isOffline) {
    if (isOffline || rssi == null || rssi <= -90) {
      return 'No connection';
    }
    if (rssi >= -70) {
      return 'Good ($rssi dBm)';
    }
    return 'Weak ($rssi dBm)';
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
                  offset: const Offset(0, 4),
                ),
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
        Positioned(
          left: 16,
          bottom: 16,
          child: _WifiLegend(),
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

class _WifiLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendItem(color: Colors.green, label: 'Good'),
          SizedBox(height: 6),
          _LegendItem(color: Colors.orange, label: 'Weak'),
          SizedBox(height: 6),
          _LegendItem(color: Colors.red, label: 'No WiFi'),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
