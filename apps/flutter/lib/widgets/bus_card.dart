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
  final VoidCallback? onRingBell;

  const BusCard({
    super.key,
    required this.bus,
    this.routeInfo,
    this.passengerCount = 0,
    required this.onTap,
    this.onRingBell,
  });

  @override
  Widget build(BuildContext context) {
    final isOffline = bus.isOffline;
    
    final currentPassengers = bus.personCount ?? passengerCount;
    // For PM2.5 dot color. Assuming green if < 35, yellow if < 100, else red.
    final pm25Value = bus.pm25 ?? 0.0;
    Color pmColor = Colors.green;
    if (pm25Value >= 35) pmColor = Colors.yellow;
    if (pm25Value >= 100) pmColor = Colors.red;

    return Opacity(
      opacity: isOffline ? 0.5 : 1.0,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top row: Name & Route on Left, Signal on Right
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${bus.busName}${bus.busMac == "DEBUG-BUS-01" ? " (Test)" : ""}${isOffline ? " (Offline)" : " (Online)"}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2D3748),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            routeInfo?.route.routeName ?? 'ไม่มีเส้นทาง',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF718096),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (bus.rssi != null) _buildSignalBadge(bus.rssi!),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // Middle Section (Data Box)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFEDF2F7)),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // NEXT STOP
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'NEXT STOP',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFA0AEC0),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              routeInfo?.nextStop?.stopName ?? '-',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D3748),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 32, color: const Color(0xFFE2E8F0)),
                      
                      // PASSENGERS
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text(
                              'PASSENGERS',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFA0AEC0),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$currentPassengers/33',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D3748),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 32, color: const Color(0xFFE2E8F0)),
                      
                      // PM 2.5
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'PM 2.5',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFA0AEC0),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: pmColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    pm25Value == pm25Value.toInt() 
                                        ? pm25Value.toInt().toString() 
                                        : pm25Value.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2D3748),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Bottom Button
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: onRingBell ?? () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF6C852), // Yellow color from image
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications, size: 20), // Bell icon
                        SizedBox(width: 8),
                        Text(
                          'RING BELL',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignalBadge(int rssi) {
    IconData icon;
    Color color;
    String label;
    if (rssi >= -55) { 
      icon = Icons.signal_wifi_4_bar; 
      color = const Color(0xFF48BB78); 
      label = 'Excellent';
    } else if (rssi >= -65) { 
      icon = Icons.network_wifi_3_bar; 
      color = const Color(0xFF48BB78); 
      label = 'Good';
    } else if (rssi >= -75) { 
      icon = Icons.network_wifi_2_bar; 
      color = const Color(0xFFECC94B); 
      label = 'Fair';
    } else if (rssi >= -85) { 
      icon = Icons.network_wifi_1_bar; 
      color = const Color(0xFFED8936); 
      label = 'Weak';
    } else { 
      icon = Icons.signal_wifi_0_bar; 
      color = const Color(0xFFE53E3E); 
      label = 'Poor';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 4),
              Text(
                '$rssi dBm',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFFA0AEC0),
            ),
          ),
        ],
      ),
    );
  }
}
