# Google Play Data Safety Worksheet

Last reviewed: 2026-05-19

Use this as the working source for the Play Console Data safety form. Re-check it before submission against the exact production build and backend behavior.

## Collection Summary

The production app should not ship a client API secret. Public app traffic uses HTTPS and secure WebSocket endpoints.

Data types likely collected:

- Location: approximate and precise location while the app is in use.
- App-generated identifier: random installation ID used for ride sessions and bell verification.
- User-provided content: feedback message and optional name.
- App interactions: ride session status, selected bus, bell requests, timestamps.
- App preferences: theme, language, notification setting, and legal consent stored locally on the device.

Data types intentionally not collected by the release build:

- Hardware device ID from `device_info_plus`; release builds now skip this debug-only read.
- Background location; the Android manifest no longer requests `ACCESS_BACKGROUND_LOCATION`.
- Account data; the app does not create user accounts.
- Advertising ID; the app does not use ads.

## Suggested Play Console Answers

### Location

- Collected: Yes.
- Shared: No sale of data. Operational access may exist for authorized maintainers/service providers.
- Purpose: App functionality, safety/security/fraud prevention for ride and bell workflows, analytics/operations.
- Required or optional: Optional for general route browsing, required for nearby bus, ride, and bell features.
- Processed ephemerally: No, ride sessions may store recent location verification values temporarily.

### User IDs

- Collected: Yes, app-generated installation ID.
- Shared: No sale of data. Operational access may exist for authorized maintainers/service providers.
- Purpose: App functionality and abuse prevention for ride sessions and bell use.
- Required or optional: Required only for ride and bell features.

### User-Provided Content

- Collected: Yes, feedback message and optional name.
- Shared: No sale of data. Operational access may exist for authorized maintainers/service providers.
- Purpose: App functionality, support, and service improvement.
- Required or optional: Optional.

### App Activity

- Collected: Yes, ride session and interaction data related to selected bus and bell use.
- Shared: No sale of data. Operational access may exist for authorized maintainers/service providers.
- Purpose: App functionality, security, analytics/operations.
- Required or optional: Required only when using ride and bell features.

### Diagnostics

- Collected: Check production backend/logging before submission.
- Recommendation: Avoid storing precise user location or full feedback payloads in logs. Keep crash/diagnostic collection undeclared unless a crash SDK or backend diagnostic collection is added.

## Security Practices

- Data encrypted in transit: Yes for production API over HTTPS and MQTT WebSocket over WSS.
- Users can request data deletion: Use the published support/privacy contact until a self-service deletion page exists.
- Independent security review: No, unless one is completed before launch.

## App Content Notes

- Ads: No.
- Account creation: No.
- Children/families: Not designed for children; target university transport community.
- Background location declaration: Not needed after removing `ACCESS_BACKGROUND_LOCATION`.
- Sensitive permissions declaration: Foreground location still needs clear in-app permission context.
