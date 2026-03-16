import 'package:flutter/material.dart';
import '../models/bus.dart';
import '../models/route_model.dart';
import '../utils/route_helpers.dart';

class BusRouteInfo {
  final BusRoute route;
  final NextStopResult? nextStop;
  BusRouteInfo({required this.route, this.nextStop});
}

class BusCard extends StatelessWidget {
  final Bus bus;
  final BusRouteInfo? routeInfo;
  final int passengerCount;
  final VoidCallback onTap;

  const BusCard({
    super.key,
    required this.bus,
    this.routeInfo,
    this.passengerCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOffline = bus.isOffline;

    return Opacity(
      opacity: isOffline ? 0.5 : 1.0,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Header row: icon + name + chevron
                Row(
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.directions_bus, size: 28,
                          color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${bus.busName}${isOffline ? " (Offline)" : ""}',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (bus.rssi != null) ...[
                                const SizedBox(width: 8),
                                _buildSignalIcon(bus.rssi!),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          if (routeInfo != null)
                            Text('🛣️ ${routeInfo!.route.routeName}',
                                style: TextStyle(color: theme.colorScheme.primary, fontSize: 14))
                          else
                            Text('No route assigned',
                                style: TextStyle(color: theme.disabledColor,
                                    fontSize: 13, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: theme.disabledColor),
                  ],
                ),

                // Next stop pill
                if (routeInfo?.nextStop != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_on, size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text('Next Stop: ', style: theme.textTheme.bodySmall),
                        Expanded(
                          child: Text(routeInfo!.nextStop!.stopName,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        if (routeInfo!.nextStop!.etaMinutes != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('~${routeInfo!.nextStop!.etaMinutes} min',
                                style: const TextStyle(color: Colors.white,
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                  ),
                ],

                // Stats row
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (bus.pm25 != null) ...[
                      Icon(Icons.eco, size: 14, color: Colors.green[600]),
                      const SizedBox(width: 4),
                      Text('PM2.5: ${bus.pm25!.toStringAsFixed(1)}',
                          style: theme.textTheme.bodySmall),
                      const SizedBox(width: 16),
                    ],
                    Icon(Icons.people, size: 14, color: Colors.purple[400]),
                    const SizedBox(width: 4),
                    Text('Passengers: $passengerCount/33',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignalIcon(int rssi) {
    IconData icon;
    Color color;
    if (rssi >= -55) { icon = Icons.signal_wifi_4_bar; color = const Color(0xFF10B981); }
    else if (rssi >= -65) { icon = Icons.network_wifi_3_bar; color = const Color(0xFF10B981); }
    else if (rssi >= -75) { icon = Icons.network_wifi_2_bar; color = const Color(0xFFF59E0B); }
    else if (rssi >= -85) { icon = Icons.network_wifi_1_bar; color = const Color(0xFFF97316); }
    else { icon = Icons.signal_wifi_0_bar; color = const Color(0xFFEF4444); }
    return Icon(icon, size: 20, color: color);
  }
}
