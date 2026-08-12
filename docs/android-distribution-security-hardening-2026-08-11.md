# Android Distribution Security Hardening — Completion Report

**Date:** 2026-08-11

**Source commit:** `9d54aea94f03c255d31af1dc40b27d59e88b2f1c`

**Package:** `com.vizcorp.moonlight_jujo_stream`

**Version:** `1.1.23+24`

## Delivered

- Added `play` and `directFire` Gradle flavors without application ID suffix.
- Play artifact has no `REQUEST_INSTALL_PACKAGES`, update `FileProvider`, native
  installer bridge, GitHub updater entrypoint, or direct-update UI.
- Fire artifact retains direct updates and rejects untrusted repository/host,
  wrong size/hash/package/version/signer, malformed APK, and redirects outside
  the allowlist before opening Android's user-approved installer.
- Preserved existing package and app-signing certificate.
- Migrated client RSA identity/private key transactionally to Android
  Keystore-backed `flutter_secure_storage`; failed migration preserves legacy
  source and never regenerates a valid identity.
- Added explicit Notification Access disclosure.
- Notification Mirror payloads use AES-256-GCM authenticated encryption,
  timestamp validation, unique nonce, bounded payload, private-LAN endpoints,
  redirect rejection, and replay rejection.
- Companion no longer starts merely because device is a TV. It binds only to a
  private non-mobile/non-VPN IPv4 address, uses 10-minute random access sessions,
  authenticates administrative routes, rejects CORS preflight, and no longer
  returns Steam/RAWG API-key values.
- CI builds only approved flavor/entrypoint pairs, runs full Flutter tests,
  produces Play APK/AAB plus Fire APK, and verifies package, permission split,
  and signer.
- Added reusable artifact verifier and distribution runbook.

## Atomic commits

- `3d3322b` — secure client identity migration
- `8f11595` — Play/Fire distribution split and hardened Fire updater
- `0bb67f1` — Companion and Notification Mirror transport protection
- `1415adf` — CI artifact contracts and release runbook
- `9d54aea` — deterministic secure-store test injection

## Final artifacts

| Channel | Artifact | SHA-256 |
| --- | --- | --- |
| Play test APK | `build/app/outputs/flutter-apk/app-play-release.apk` | `46518B59FD7DE76350E606F58D6BEA03B474B73E292DDB4246F4B1161B918F85` |
| Play AAB | `build/app/outputs/bundle/playRelease/app-play-release.aab` | `5199D085131B12A82E9453D58D7FAEED50662E4E1E4FC8F15601A880286565E1` |
| Fire TV APK | `build/app/outputs/flutter-apk/app-directfire-release.apk` | `EE4B139E1A0DEAD87FC2CF1C8B53D3928E2888F4F739332CE5B43FD59CFE7863` |

All APKs use certificate SHA-256
`EC0769DC9D131705AF4CEEA71F520F9C31482283F16A8F581937EE5E68D8E749`.

## Verification

- Focused analyzer: clean.
- Full Flutter suite: 201 tests passed.
- Play APK release: built.
- Play AAB release: built.
- Fire APK release: built.
- Artifact contract script: passed.
- Play permission inspection: no `REQUEST_INSTALL_PACKAGES`.
- Fire permission inspection: `REQUEST_INSTALL_PACKAGES` present.
- Play native/Dart updater marker inspection: absent.
- Fire native/Dart updater marker inspection: present.

## Physical-device status

`adb start-server` succeeded, but `adb devices -l` returned no serials. No APK
was installed and no logcat claim is made in this report. When devices reconnect:

```powershell
adb -s <chromecast-serial> install -r build/app/outputs/flutter-apk/app-play-release.apk
adb -s <fire-serial> install -r build/app/outputs/flutter-apk/app-directfire-release.apk
```

Production Chromecast qualification must use the Play internal track and the
Play-delivered APK, not only the local Play-flavor APK.

## Remaining external steps

1. Import existing signing key into Play App Signing; verify Play-delivered
   certificate before rollout.
2. Run device upgrade/stream/controller/Notification Mirror matrix when ADB
   serials are visible.
3. Submit final delivered hashes to Play Protect and Safe Browsing if warnings
   remain. Code changes cannot manufacture Chrome download reputation.

Notification peer records still retain compatibility data in preferences. The
high-value client private key is migrated to Keystore and notification bodies
are encrypted in transit; moving every legacy peer record into secure storage
should be a separate bridge migration so existing pairings are not invalidated.

The browser-based Companion UI still uses HTTP on the private LAN because an
untrusted per-device certificate would make ordinary TV/phone browsers reject
the page. Administrative routes now require an expiring authenticated session
and never return stored API-key values, but transport-level TLS requires a
separate certificate-trust/onboarding design. This limitation does not exist for
Notification Mirror bodies, which are encrypted and authenticated end to end.
