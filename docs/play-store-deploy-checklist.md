# SUT Smart Bus Play Store Deploy Checklist

Last reviewed: 2026-05-19

Scope: Android / Google Play first. iOS/App Store can follow after the Android release path is stable.

## Current P0 Blockers

- [x] Configure real Android release signing. The repo now uses `android/key.properties` and a generated local upload keystore instead of debug signing for release builds.
- [x] Remove `ACCESS_BACKGROUND_LOCATION`; the app now requests foreground location only.
- [x] Remove the client-shipped API key from the default Flutter build. `Env.apiSecretKey` now defaults to empty and can only be injected with `--dart-define` for private builds.
- [ ] Rotate the previously exposed production server API key before launch.
- [x] Verify production debug/test features cannot mutate live bus data for normal users. Release builds now skip privileged client calls unless an API key is explicitly injected, and `/api/debug/*` is no longer public when backend auth is enabled.
- [ ] Publish a public, non-PDF privacy policy URL. Draft is ready at `docs/play-store/privacy-policy.html`.
- [x] Confirm notification behavior on Android 13+. No actual notification delivery path is present, so `POST_NOTIFICATIONS` is not declared for this release.
- [ ] Restore/verify production backend availability. `https://bus-api.catcode.tech/health` returned Cloudflare 530 on 2026-05-19.

## Release Identity

- [x] Finalize the Play package name before creating the Play Console app: `com.sut.smartbus.sut_smart_bus`. Package names are permanent and cannot be reused.
- [x] Remove the starter TODO comment around `applicationId` once the ID is final.
- [x] Confirm app name: `SUT Smart Bus`.
- [ ] Confirm Play listing developer name, support email, website, and privacy contact.
- [ ] Confirm countries/regions for first launch, likely Thailand first.
- [ ] Confirm app category: likely `Travel & Local`, `Maps & Navigation`, or university/internal transport depending on positioning.
- [ ] Confirm app is free and has no ads or in-app purchases unless that changes.

## Android Build And Signing

- [x] Add release upload key material outside git, for example:
  - `apps/flutter/android/key.properties`
  - a local or CI-protected `.jks` upload keystore
- [x] Add `key.properties`, `*.jks`, and `*.keystore` to `.gitignore` before generating real keys.
- [x] Update `apps/flutter/android/app/build.gradle.kts` so `release` uses `signingConfigs.getByName("release")`.
- [ ] Enroll the app in Play App Signing and use an upload key for app bundle uploads.
- [x] Keep `compileSdk` and `targetSdk` at or above the current Play requirement. Current repo values are `36`, which satisfies the current API 35+ submission requirement.
- [x] Bump `version` in `apps/flutter/pubspec.yaml` for each upload. Current initial release value is `1.0.0+1`, where `+1` becomes Android `versionCode`.
- [x] Build the Play artifact from `apps/flutter/`:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
```

- [ ] Upload `apps/flutter/build/app/outputs/bundle/release/app-release.aab` to Play Console. Latest local build succeeded, produced a 44.5 MB AAB, and `jarsigner -verify` succeeded.
- [ ] Save the generated mapping/symbol files if Play Console requests deobfuscation or native symbols.

## Permissions And Policy

- [x] Inventory actual data collection before filling Play Data safety. Worksheet: `docs/play-store/data-safety-worksheet.md`.
  - device location: map/nearby bus features
  - device identifiers: `device_info_plus` debug provider reads Android/iOS device IDs
  - diagnostics/debug data, if sent to the server
  - feedback name and message
  - app preferences stored locally through `shared_preferences`
- [ ] Declare only what is actually collected, shared, optional, required, encrypted in transit, and deletable.
- [ ] Ensure privacy policy and Data safety answers match the app behavior and each other.
- [ ] If keeping background location:
  - prominent in-app disclosure must appear before the runtime location permission
  - disclosure must say "location" and explain background use
  - Play Console declaration must include a review video
  - store listing must make the core background-location feature clear
- [x] If background location is not essential, remove `ACCESS_BACKGROUND_LOCATION` from all active tracks before review.
- [x] Check whether `RECEIVE_BOOT_COMPLETED` is really needed. Removed because no boot-time notification/scheduling path is active.
- [x] Add `POST_NOTIFICATIONS` and runtime request flow if notifications are used on Android 13+. Not needed for this release because no user-visible notification delivery path is active.
- [ ] Complete Play Console App content sections:
  - Data safety
  - Content rating questionnaire
  - Target audience and content
  - Privacy policy
  - Ads declaration
  - App access instructions, if any feature is gated
  - Sensitive permissions declarations

## Backend And Production Environment

- [ ] Run the backend production stack with the tunnel overlay. Blocked locally because Docker is not installed or not on PATH.

```powershell
docker-compose -f docker-compose.yml -f docker-compose.tunnel.yml up -d --build
```

- [ ] Verify public API health. Current result on 2026-05-19: Cloudflare 530.

```powershell
curl https://bus-api.catcode.tech/health
```

- [ ] Verify MQTT over WebSocket/TLS from a real Android device on mobile data and campus Wi-Fi.
- [ ] Rotate production `API_SECRET_KEY` and `ADMIN_PASSWORD` before launch.
- [ ] Restrict CORS for production where possible.
- [ ] Confirm rate limits are suitable for Play traffic.
- [ ] Confirm MongoDB persistence/backups and restore steps.
- [ ] Confirm logs do not store unnecessary precise user location or feedback personal data.
- [ ] Confirm OTA/hardware endpoints are protected and cannot be triggered by public app users.

## App Readiness QA

- [x] Run `flutter analyze`; passed on 2026-05-19.
- [x] Run `flutter test`; passed on 2026-05-19.
- [ ] Install a release build on at least one physical Android 13+ device and one older supported Android device.
- [ ] Test first launch, legal consent, settings, map, route list, air quality, Wi-Fi heatmap, and feedback submission.
- [ ] Test permission flows:
  - location denied
  - location denied forever
  - location allowed while using app
  - notifications denied/allowed, if used
- [ ] Test offline behavior and backend timeout behavior.
- [ ] Test MQTT reconnect after app background/resume and network changes.
- [ ] Test Thai and English UI strings on small screens.
- [ ] Confirm debug/test buses are hidden from normal users.
- [ ] Confirm no release screen exposes secret keys, admin controls, fake camera streams, spoof controls, or local-only URLs.
- [ ] Run backend smoke checks. Current local/public checks failed because local server is not running and the public tunnel returned Cloudflare 530:

```powershell
curl http://localhost:8000/health
curl https://bus-api.catcode.tech/health
```

## Store Listing Assets

- [x] App icon: 512 x 512 PNG for Play Console. Generated at `docs/play-store/assets/app-icon-512.png`.
- [x] Feature graphic: 1024 x 500 PNG. Generated at `docs/play-store/assets/feature-graphic-1024x500.png`.
- [ ] Phone screenshots showing actual app screens:
  - live map / bus locations
  - routes
  - air quality
  - settings/legal or feedback
- [x] Short description in English and Thai. Draft: `docs/play-store/store-listing.md`.
- [x] Full description in English and Thai. Draft: `docs/play-store/store-listing.md`.
- [ ] Privacy policy URL. HTML draft exists locally, but must be hosted publicly.
- [ ] Support email.
- [ ] Optional website/project URL.
- [x] Release notes for `1.0.0`. Draft: `docs/play-store/store-listing.md`.

## Play Console Test Tracks

- [ ] Create the app in Play Console only after package name and app name are final.
- [ ] Upload first AAB to Internal testing.
- [ ] Review Play pre-launch report for stability, compatibility, performance, accessibility, and screenshots.
- [ ] Fix all Play Console errors and high-signal warnings.
- [ ] If using a personal developer account created after 2023-11-13, run closed testing with at least 12 opted-in testers for 14 continuous days before production access.
- [ ] Run a closed test with real campus users even if the account does not require it.
- [ ] Collect tester feedback on:
  - bus location accuracy
  - ETA usefulness
  - map readability
  - permission prompts
  - battery/network behavior
  - Thai/English wording

## Production Launch

- [ ] Confirm no active Play testing artifact contains background location or debug behavior that was removed later.
- [ ] Confirm production country availability.
- [ ] Confirm backend, MQTT, database, and tunnel monitoring are active.
- [ ] Upload production AAB.
- [ ] Resolve Play review errors.
- [ ] Start rollout. Note: first production release does not support staged rollout percentage; it goes live to selected countries when approved and published.
- [ ] Monitor after launch:
  - Play vitals crashes and ANRs
  - pre-launch report regressions
  - backend logs and rate limits
  - MQTT connection errors
  - feedback submissions
  - bad route/telemetry data

## Post-Launch Maintenance

- [ ] Increase `versionCode` for every update.
- [ ] Keep `targetSdk` aligned with Play's annual target API deadlines.
- [ ] Update Data safety whenever data collection, sharing, retention, or SDK behavior changes.
- [ ] Re-run full permission review before adding location, notification, camera, microphone, storage, account, or ads features.
- [ ] Keep release notes and screenshots current when major UI/features change.

## Official References

- [Flutter: Build and release an Android app](https://docs.flutter.dev/deployment/android)
- [Google Play target API level requirement](https://developer.android.com/google/play/requirements/target-sdk)
- [Android App Bundles](https://developer.android.com/guide/app-bundle)
- [Play Console: create and set up your app](https://support.google.com/googleplay/android-developer/answer/9859152)
- [Play Console: prepare and roll out a release](https://support.google.com/googleplay/android-developer/answer/9859348)
- [Play Console: Data safety section](https://support.google.com/googleplay/android-developer/answer/10787469)
- [Play Console: background location permissions](https://support.google.com/googleplay/android-developer/answer/9799150)
- [Android 13 notification runtime permission](https://developer.android.com/develop/ui/views/notifications/notification-permission)
- [Play Console: pre-launch reports](https://support.google.com/googleplay/android-developer/answer/9842757)
- [Play Console: testing requirements for new personal accounts](https://support.google.com/googleplay/android-developer/answer/14151465)
- [Play Console: content ratings](https://support.google.com/googleplay/android-developer/answer/9898843)
