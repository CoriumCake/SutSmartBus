# 13 — Build, Signing & Deployment

## Purpose
Guide the build, signing, and deployment process for the Flutter app on Android and iOS.

---

## 1. Environment Variables for Production

### Using `--dart-define` at build time

```bash
flutter run \
  --dart-define=CONNECTION_MODE=tunnel \
  --dart-define=API_URL=https://api.sutsmartbus.example.com \
  --dart-define=MQTT_BROKER_HOST=mqtt.sutsmartbus.example.com \
  --dart-define=MQTT_WS_PORT=9001 \
  --dart-define=API_SECRET_KEY=your_secret_key
```

These values are accessed in `lib/config/env.dart` via `String.fromEnvironment`.

---

## 2. App Icon & Splash Screen

### App Icon

Use `flutter_launcher_icons` package:

```yaml
# pubspec.yaml (dev_dependencies)
dev_dependencies:
  flutter_launcher_icons: ^0.14.3

# Add this section
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/images/app_icon.png"
  adaptive_icon_background: "#F57C00"
  adaptive_icon_foreground: "assets/images/app_icon_foreground.png"
```

```bash
flutter pub run flutter_launcher_icons
```

### Splash Screen

Use `flutter_native_splash`:

```yaml
dev_dependencies:
  flutter_native_splash: ^2.4.3

flutter_native_splash:
  color: "#F57C00"
  image: "assets/images/splash_logo.png"
  android_12:
    color: "#F57C00"
    icon_background_color: "#F57C00"
    image: "assets/images/splash_logo.png"
```

```bash
flutter pub run flutter_native_splash:create
```

---

## 3. Android Build

### Update App Info

#### `android/app/build.gradle`

```groovy
android {
    namespace "com.sut.smartbus"
    compileSdkVersion 34

    defaultConfig {
        applicationId "com.sut.smartbus"
        minSdkVersion 21
        targetSdkVersion 34
        versionCode 1
        versionName "1.0.0"
    }

    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
        }
    }
}
```

### Create Signing Key

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

### Create `android/key.properties`

```properties
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=upload
storeFile=/path/to/upload-keystore.jks
```

### Build APK

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release \
  --dart-define=CONNECTION_MODE=tunnel \
  --dart-define=API_URL=https://api.sutsmartbus.example.com

# Release App Bundle (for Google Play)
flutter build appbundle --release
```

### Output Locations
- APK: `build/app/outputs/flutter-apk/app-release.apk`
- AAB: `build/app/outputs/bundle/release/app-release.aab`

---

## 4. iOS Build

### Update App Info

#### `ios/Runner/Info.plist`

Ensure these keys are set:
- `CFBundleDisplayName`: "SUT Smart Bus"
- `CFBundleIdentifier`: `com.sut.smartbus`
- `CFBundleShortVersionString`: "1.0.0"
- `CFBundleVersion`: "1"

### Build Steps

```bash
# Install pods
cd ios && pod install && cd ..

# Build for iOS (requires macOS + Xcode)
flutter build ios --release \
  --dart-define=CONNECTION_MODE=tunnel \
  --dart-define=API_URL=https://api.sutsmartbus.example.com
```

### Xcode Archive
1. Open `ios/Runner.xcworkspace` in Xcode
2. Select "Any iOS Device" as target
3. Product → Archive
4. Distribute App → App Store Connect

---

## 5. Deployment Checklist

### Pre-deployment

- [ ] All tests pass: `flutter test`
- [ ] App runs correctly on Android emulator
- [ ] App runs correctly on iOS simulator (if on macOS)
- [ ] App runs correctly on physical device
- [ ] MQTT connection works in production mode
- [ ] API calls work with production server
- [ ] Dark mode works correctly
- [ ] Both languages (EN/TH) render correctly
- [ ] Notifications work when enabled
- [ ] Map renders with correct SUT campus coordinates
- [ ] Bus tracking updates in real-time

### Release

- [ ] Version number incremented in `pubspec.yaml`
- [ ] App icon generated and looks correct
- [ ] Splash screen displays correctly
- [ ] Release APK/AAB signed and builds without errors
- [ ] ProGuard/R8 doesn't strip required classes
- [ ] Google Maps API key is configured for production

### Post-deployment

- [ ] App installs from generated APK
- [ ] All features work on fresh install
- [ ] Theme preference persists after restart
- [ ] Language preference persists after restart
- [ ] Route data loads from server

---

## 6. CI/CD (Optional)

### GitHub Actions workflow for Flutter

```yaml
# .github/workflows/flutter.yml
name: Flutter CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
      - run: flutter pub get
        working-directory: apps/flutter
      - run: flutter test
        working-directory: apps/flutter
      - run: flutter build apk --release
        working-directory: apps/flutter
      - uses: actions/upload-artifact@v4
        with:
          name: release-apk
          path: apps/flutter/build/app/outputs/flutter-apk/app-release.apk
```

---

## Notes for Agent

- The React Native project's Google Maps API key (found in `android/app/src/main/AndroidManifest.xml`) should be reused.
- Production environment variables should be provided by the user — do not hardcode production secrets.
- The iOS build requires macOS with Xcode installed. If the user is on Windows, only the Android build can be performed locally.
- The app should be tested with the real backend server before deploying to production.
