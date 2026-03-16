# 01 — Flutter Project Setup

## Purpose
Initialize a new Flutter project for SUT Smart Bus, install all required dependencies, and configure platform-specific settings (Android manifest, iOS plist, Google Maps API key).

## Source Files Being Replaced
- `apps/mobile/package.json` → `apps/flutter/pubspec.yaml`
- `apps/mobile/app.config.js` → `apps/flutter/android/app/build.gradle` + `ios/Runner/Info.plist`
- `apps/mobile/babel.config.js` → Not needed (Dart has no transpilation)
- `apps/mobile/metro.config.js` → Not needed (Flutter has its own build system)

---

## Step 1: Create Flutter Project

```bash
cd l:\Coding\SutSmartBus\apps
flutter create --org com.sut.smartbus --project-name sut_smart_bus --platforms android,ios flutter
cd flutter
```

## Step 2: Replace `pubspec.yaml`

Replace the generated `pubspec.yaml` with:

```yaml
name: sut_smart_bus
description: Smart transit & environmental monitoring for Suranaree University
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.5.0
  flutter: ">=3.24.0"

dependencies:
  flutter:
    sdk: flutter

  # State Management
  flutter_riverpod: ^2.6.1
  riverpod_annotation: ^2.6.1

  # Navigation
  go_router: ^14.6.2

  # Maps & Location
  google_maps_flutter: ^2.10.0
  geolocator: ^13.0.2
  geocoding: ^3.0.0

  # Networking
  dio: ^5.7.0
  mqtt_client: ^10.6.0

  # Storage
  shared_preferences: ^2.3.4
  hive: ^2.2.3
  hive_flutter: ^1.1.0

  # Notifications
  flutter_local_notifications: ^18.0.1
  permission_handler: ^11.3.1

  # UI
  material_design_icons_flutter: ^7.0.7296
  google_fonts: ^6.2.1
  shimmer: ^3.0.0
  cached_network_image: ^3.4.1

  # Device Info
  device_info_plus: ^11.2.0
  package_info_plus: ^8.1.3

  # Utils
  intl: ^0.19.0
  url_launcher: ^6.3.1
  flutter_secure_storage: ^9.2.3

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  build_runner: ^2.4.13
  riverpod_generator: ^2.6.3
  hive_generator: ^2.0.1
  mockito: ^5.4.4
  build_runner: ^2.4.13

flutter:
  uses-material-design: true

  assets:
    - assets/images/
    - assets/routes/
```

## Step 3: Create Directory Structure

```bash
# From apps/flutter/
mkdir -p lib/models
mkdir -p lib/providers
mkdir -p lib/services
mkdir -p lib/screens
mkdir -p lib/widgets
mkdir -p lib/utils
mkdir -p lib/config
mkdir -p lib/l10n
mkdir -p assets/images
mkdir -p assets/routes
```

## Step 4: Copy Assets

```bash
# Copy bus icon from React Native project
cp ../mobile/assets/W-bus-icon.png assets/images/bus_icon.png

# Copy bundled route data
cp ../mobile/routes/red_routes.json assets/routes/red_routes.json
```

## Step 5: Android Configuration

### `android/app/src/main/AndroidManifest.xml`

Add these permissions and the Google Maps API key inside `<application>`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- Permissions -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>

    <application
        android:label="SUT Smart Bus"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">

        <!-- Google Maps API Key -->
        <meta-data
            android:name="com.google.android.geo.API_KEY"
            android:value="YOUR_GOOGLE_MAPS_API_KEY"/>

        <!-- ... rest of manifest -->
    </application>
</manifest>
```

### `android/app/build.gradle`

Ensure `minSdkVersion` is set to at least 21:

```groovy
android {
    defaultConfig {
        minSdkVersion 21
        targetSdkVersion 34
        // ...
    }
}
```

## Step 6: iOS Configuration

### `ios/Runner/AppDelegate.swift`

Add Google Maps initialization:

```swift
import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("YOUR_GOOGLE_MAPS_API_KEY")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

### `ios/Runner/Info.plist`

Add location permission strings:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>SUT Smart Bus needs your location to show nearby bus stops and track your position on the map.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>SUT Smart Bus needs your location to notify you when buses are approaching.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>SUT Smart Bus uses your location to track nearby buses and send arrival notifications.</string>
```

## Step 7: Install Dependencies

```bash
flutter pub get
```

## Step 8: Verify Setup

```bash
flutter doctor
flutter run
```

---

## Verification Checklist

- [ ] `flutter create` runs successfully
- [ ] `flutter pub get` resolves all dependencies without errors
- [ ] `flutter run` launches the default counter app on a device/emulator
- [ ] Google Maps API key is configured in both Android and iOS
- [ ] Assets directory contains `bus_icon.png` and `red_routes.json`
- [ ] Directory structure matches the plan above

---

## Notes for Agent

- The Google Maps API key should be obtained from the existing React Native project's `android/app/src/main/AndroidManifest.xml` or the Expo config.
- If the user doesn't have a Google Maps API key configured, ask them to provide one.
- The `build_runner` is listed for code generation (Riverpod generators, Hive adapters).
