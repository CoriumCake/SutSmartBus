# SUT Smart Bus

Flutter client for the SUT Smart Bus project.

## Run on iPhone

Prerequisites:

- macOS with Xcode installed.
- Flutter SDK 3.24 or newer in your PATH.
- CocoaPods installed with `sudo gem install cocoapods` or `brew install cocoapods`.
- A physical iPhone connected by USB, or an iOS Simulator.

Setup:

```sh
cd apps/flutter
flutter doctor
flutter pub get
cd ios
pod install
cd ..
```

Run with the hosted tunnel backend:

```sh
flutter run -d <device-id>
```

Run with a local backend on the same Wi-Fi network:

```sh
flutter run -d <device-id> \
  --dart-define=CONNECTION_MODE=local \
  --dart-define=SERVER_IP=<your-mac-lan-ip> \
  --dart-define=MQTT_BROKER_HOST=<your-mac-lan-ip>
```

Use the Mac's LAN IP, for example `192.168.1.23`, not `localhost`. On a real
iPhone, `localhost` means the phone itself.

Before running on a physical iPhone, open `ios/Runner.xcworkspace` in Xcode,
select the `Runner` target, choose your Apple Development Team, and make sure
the Bundle Identifier is unique for your Apple account.
