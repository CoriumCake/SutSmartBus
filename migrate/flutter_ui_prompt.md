# Flutter UI Prompt

Copy everything below this line and paste it to another AI model:

---

Create a beautiful, premium Flutter mobile app called **SUT Smart Bus** — a real-time university bus tracker with air quality monitoring. Build **only the frontend UI** using hardcoded mock data (no real API calls). Focus on making it look stunning, polished, and modern.

## Brand & Theme

- **Primary color**: SUT Orange `#F57C00` (light mode), `#FFB74D` (dark mode)
- **Backgrounds**: `#FFFFFF` light / `#121212` dark
- **Cards**: `#FFFFFF` light / `#252525` dark
- **Text**: `#333333` light / `#FFFFFF` dark
- **Muted text**: `#999999` light / `#707070` dark
- **Font**: Inter (via `google_fonts` package)
- **Style**: Material 3, rounded cards (radius 12-16), subtle shadows, smooth micro-animations
- Support **dark mode toggle** via a theme provider

## Navigation

Bottom navigation with 4 tabs:
1. **Map** (icon: map) — Main map screen
2. **Routes** (icon: list) — Bus list
3. **Air Quality** (icon: cloud) — PM2.5 monitoring
4. **Settings** (icon: settings) — Preferences

Stack screens pushed on top of tabs: About, Bus Management, Route Admin

## Screen 1: Map Screen
- Full-screen Google Map centered on SUT campus (lat: 14.8820, lon: 102.0207, zoom: 15.5)
- Display 3 mock bus markers with custom orange bus icons
- Show a colored route polyline connecting waypoints
- "Locate Me" FAB (bottom-right)
- Bottom panel showing "Nearby Stop: Engineering Building — 2 incoming buses"
  - Each incoming bus shows: route color dot, bus name, ETA badge ("~3 min")

## Screen 2: Routes Screen
- Header: "Routes" with active bus count banner ("3 active buses")
- List of bus cards, each with:
  - Bus icon in rounded orange container + bus name + WiFi signal icon
  - Route name (e.g., "🛣️ Red Line Campus Loop")
  - "Next Stop" pill with location icon + stop name + orange ETA badge ("~5 min")
  - Stats row: green leaf icon + PM2.5 value, purple people icon + passenger count
- Cards have rounded corners (16px), subtle shadow, tap ripple effect
- Offline buses show at 50% opacity with "OFFLINE" badge
- Pull-to-refresh support

## Screen 3: Air Quality Screen
- **Top half**: Map with colored semi-transparent polygon tiles forming a PM2.5 heatmap grid
  - Green (good ≤25), Yellow (moderate 25-50), Orange (sensitive 50-75), Red (unhealthy >75)
  - Time filter buttons: "1h" / "24h" toggle
- **Bottom half**: Scrollable cards titled "Live Bus Air Quality"
  - Each card: bus name + colored status badge (Good/Moderate/Unhealthy)
  - PM2.5 + PM10 values in µg/m³
  - Temperature (°C) + Humidity (%)
  - Bottom panel slides up with rounded top corners and subtle shadow

## Screen 4: Settings Screen
- Clean list of setting items, each in a rounded card:
  - 🎨 Dark Mode — Switch toggle
  - 🔔 Notifications — Switch toggle
  - 🌐 Language — shows "English", taps to show dialog (English / ไทย)
  - 🐛 Debug Mode — Red switch (conditional)
- Navigation links: Bus Management → , Route Admin → , About →
- Developer section (when debug on): API endpoint, device ID, API call count in a card

## Screen 5: About Screen
- Centered bus icon in large rounded orange container (100x100)
- "SUT Smart Bus" title + "Version 1.0.0"
- Description card
- Features list with colored icons: location (orange), eco (green), notifications (amber), map (purple)
- Developer info: "Suranaree University of Technology / School of Computer Engineering"
- Contact links: email + website with tap-to-open

## Mock Data to Use

```dart
final mockBuses = [
  {'name': 'SUT-Bus-01', 'lat': 14.8825, 'lon': 102.0210, 'pm25': 18.5, 'pm10': 25.0, 'temp': 32.1, 'hum': 65, 'seats': 15, 'route': 'Red Line', 'rssi': -55, 'online': true},
  {'name': 'SUT-Bus-02', 'lat': 14.8800, 'lon': 102.0190, 'pm25': 42.3, 'pm10': 55.0, 'temp': 33.5, 'hum': 58, 'seats': 8, 'route': 'Red Line', 'rssi': -72, 'online': true},
  {'name': 'SUT-Bus-03', 'lat': 14.8780, 'lon': 102.0230, 'pm25': 12.0, 'pm10': 18.0, 'temp': 31.0, 'hum': 70, 'seats': 22, 'route': 'Green Line', 'rssi': -88, 'online': false},
];

final mockStops = ['Main Gate', 'Engineering Building', 'Library', 'Dormitory', 'Sports Complex', 'Cafeteria'];
```

## Tech Stack / Dependencies

```yaml
dependencies:
  flutter_riverpod: ^2.6.1
  go_router: ^14.6.2
  google_maps_flutter: ^2.10.0
  google_fonts: ^6.2.1
  shared_preferences: ^2.3.4
  material_design_icons_flutter: ^7.0.7296
```

## Requirements
- Use `flutter_riverpod` for state management (theme, language)
- Use `go_router` with `ShellRoute` for tab navigation
- All widgets must support light AND dark mode
- Use smooth hero animations, fade transitions, and micro-interactions
- Cards should have subtle elevation/shadow that adapts to theme
- Make it feel like a premium production app, NOT a prototype
- Responsive layout that works on both phones and tablets
