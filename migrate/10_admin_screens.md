# 10 — Admin & Secondary Screens Migration

## Purpose
Migrate the remaining 5 admin/secondary screens to Flutter. These are all accessed via the Settings screen or Debug mode.

## Source Files
- `screens/BusManagementScreen.js` (333 lines) → `lib/screens/bus_management_screen.dart`
- `screens/BusRouteAdminScreen.js` (478 lines) → `lib/screens/bus_route_admin_screen.dart`
- `screens/RouteEditorScreen.js` (876 lines) → `lib/screens/route_editor_screen.dart`
- `screens/AirQualityDashboardScreen.js` (705 lines) → `lib/screens/air_quality_dashboard_screen.dart`
- `screens/AboutScreen.js` (221 lines) → `lib/screens/about_screen.dart`

---

## Screen 1: Bus Management

### Behavior
- CRUD for buses via API (`POST /api/buses`, `PUT /api/buses/:mac`, `DELETE /api/buses/:mac`)
- FlatList of registered buses
- Modal dialog for Add/Edit with fields: MAC Address + Bus Name
- Swipe or long-press to delete with confirmation

### `lib/screens/bus_management_screen.dart` (skeleton)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/data_provider.dart';
import '../models/bus.dart';

class BusManagementScreen extends ConsumerStatefulWidget {
  const BusManagementScreen({super.key});
  @override
  ConsumerState<BusManagementScreen> createState() => _BusManagementScreenState();
}

class _BusManagementScreenState extends ConsumerState<BusManagementScreen> {
  List<Bus> _registeredBuses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchBuses();
  }

  Future<void> _fetchBuses() async {
    final api = ref.read(apiServiceProvider);
    final buses = await api.fetchBuses();
    setState(() { _registeredBuses = buses; _loading = false; });
  }

  void _showAddEditDialog({Bus? existing}) {
    final macController = TextEditingController(text: existing?.macAddress ?? '');
    final nameController = TextEditingController(text: existing?.busName ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing != null ? 'Edit Bus' : 'Register Bus'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: macController,
              decoration: const InputDecoration(labelText: 'MAC Address'),
              enabled: existing == null),
          const SizedBox(height: 12),
          TextField(controller: nameController,
              decoration: const InputDecoration(labelText: 'Bus Name')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final api = ref.read(apiServiceProvider);
              if (existing != null) {
                await api.updateBus(macController.text, nameController.text);
              } else {
                await api.createBus(macController.text, nameController.text);
              }
              Navigator.pop(ctx);
              _fetchBuses();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteBus(Bus bus) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Bus'),
        content: Text('Are you sure you want to delete "${bus.busName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final api = ref.read(apiServiceProvider);
              await api.deleteBus(bus.macAddress ?? bus.busMac);
              Navigator.pop(ctx);
              _fetchBuses();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Bus Management')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _registeredBuses.length,
              itemBuilder: (context, index) {
                final bus = _registeredBuses[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                    child: Icon(Icons.directions_bus, color: theme.colorScheme.primary),
                  ),
                  title: Text(bus.busName),
                  subtitle: Text(bus.macAddress ?? bus.busMac),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.edit),
                        onPressed: () => _showAddEditDialog(existing: bus)),
                    IconButton(icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteBus(bus)),
                  ]),
                );
              },
            ),
    );
  }
}
```

---

## Screen 2: Bus Route Admin

### Behavior
- Lists all buses with a dropdown to assign a route to each bus
- Lists all saved routes with delete option
- "Sync All to Server" button
- Refresh data on pull-to-refresh

### Key Implementation Notes

```dart
// For each bus, render a DropdownButton<String> with route options
// Use BusMappingService to persist bus→route assignments
// Use RouteStorageService to list and delete routes
// Use ApiService to sync routes to server and delete from server
```

---

## Screen 3: Route Editor

### Behavior (most complex admin screen — 876 lines)
- Full-screen Google Map for creating/editing routes
- **Tap map** → add waypoint
- **Tap marker** → select it (edit name, toggle isStop)
- **Long-press marker** → delete waypoint
- **Mark as Stop** toggle on selected waypoint
- **Save** route with name + color + optional bus assignment
- Route color picker
- Load existing routes for editing
- Sync saved route to server

### Key Implementation Notes

```dart
// This is essentially a custom map editor
// Use GoogleMap with:
// - onTap → add Marker at position, append to waypoints list
// - Interactive markers (draggable)
// - Polyline connecting all waypoints
// - Bottom sheet for waypoint details (name, isStop toggle)
// - Save button that writes to RouteStorageService
//
// State to manage:
// - List<Waypoint> waypoints (ordered)
// - int? selectedWaypointIndex
// - String routeName, routeColor
// - bool isEditing (vs creating new)
//
// GridOverlay widget: draws colored grid cells over the map for debug visualization
```

---

## Screen 4: Air Quality Dashboard

### Behavior (705 lines)
- Stats cards: Avg PM2.5, Total buses reporting, Best/Worst zone
- Zone heatmap using Google Maps Polygons
- Zone ranking list
- Trend visualization (text-based bar graphs)
- Bus selector to filter data
- Time range selector (1h, 24h, 7d)
- Own MQTT connection for real-time updates
- Pull-to-refresh

### Key Implementation Notes

```dart
// This screen has its own direct MQTT connection (not shared with DataProvider)
// Use the same MqttService but create a separate instance
// Fetch analytics from /api/pm/heatmap?range=1h
// Stats computed locally from fetched data
// Trend bars are rendered using simple Container widgets with fractional width
```

---

## Screen 5: About Screen

### Behavior (simplest screen — 221 lines)
- App logo (bus icon in colored container)
- App name + version number
- Description card
- Features list (4 items with icons)
- Developer info (SUT / School of Computer Engineering)
- Contact links (email: support@sut.ac.th, web: www.sut.ac.th)
- Copyright footer

### `lib/screens/about_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/language_provider.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(languageProvider).t;

    return Scaffold(
      appBar: AppBar(title: Text(t('about'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Logo
          Center(child: Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(24)),
            child: const Icon(Icons.directions_bus, size: 48, color: Colors.white),
          )),
          const SizedBox(height: 16),
          Center(child: Text('SUT Smart Bus',
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold))),
          Center(child: Text('${t("version")} 1.0.0',
              style: theme.textTheme.bodySmall)),
          const SizedBox(height: 24),

          // Description
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(t('appDescription'), style: theme.textTheme.bodyMedium),
            ),
          ),
          const SizedBox(height: 16),

          // Features
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _featureRow(Icons.location_on, 'Real-time bus tracking', theme.colorScheme.primary),
                _featureRow(Icons.eco, 'Air quality monitoring (PM2.5)', Colors.green),
                _featureRow(Icons.notifications, 'Arrival notifications', Colors.amber),
                _featureRow(Icons.map, 'Route visualization', Colors.purple),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Developer
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Development Team', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('Suranaree University of Technology'),
                Text('School of Computer Engineering'),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Contact
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Contact & Support', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _linkRow(Icons.mail, 'support@sut.ac.th', 'mailto:support@sut.ac.th', theme),
                _linkRow(Icons.language, 'www.sut.ac.th', 'https://www.sut.ac.th', theme),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          Center(child: Text('© 2024 Suranaree University of Technology',
              style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }

  Widget _featureRow(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(text),
      ]),
    );
  }

  Widget _linkRow(IconData icon, String label, String url, ThemeData theme) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: theme.colorScheme.primary)),
        ]),
      ),
    );
  }
}
```

---

## Verification Checklist

### Bus Management
- [ ] List of registered buses loads from API
- [ ] Add bus dialog creates new bus via API
- [ ] Edit bus dialog updates bus name via API
- [ ] Delete bus shows confirmation and deletes via API

### Bus Route Admin
- [ ] Buses list with route assignment dropdown
- [ ] Route assignment persists (bus-route mapping)
- [ ] Routes list with delete option
- [ ] "Sync All" button uploads routes to server

### Route Editor
- [ ] Map tap adds waypoints
- [ ] Selected marker shows detail panel
- [ ] Waypoint can be toggled as "stop" with name
- [ ] Save creates/updates route in local storage
- [ ] Route polyline renders between all waypoints

### Air Quality Dashboard
- [ ] Stats cards show Avg PM2.5, count metrics
- [ ] Zone heatmap renders colored polygons
- [ ] Zone ranking list sorts by PM2.5
- [ ] Time range selector (1h, 24h, 7d) filters data

### About
- [ ] App logo, name, version display
- [ ] Features list renders correctly
- [ ] Contact links open in browser/email
