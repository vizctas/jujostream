# Android Distribution Runbook

## Immutable identity

- Package: `com.vizcorp.moonlight_jujo_stream`
- Certificate SHA-256: `EC0769DC9D131705AF4CEEA71F520F9C31482283F16A8F581937EE5E68D8E749`
- Import the existing app-signing key into Play App Signing. Never accept a new
  Google-generated app-signing key. A separate upload key is allowed.

## Build and verify

```powershell
flutter pub get
flutter test
flutter build apk --release --flavor play -t lib/main_play.dart
flutter build appbundle --release --flavor play -t lib/main_play.dart
flutter build apk --release --flavor directFire -t lib/main_direct_fire.dart
pwsh scripts/verify_android_release_artifacts.ps1 `
  -PlayApk build/app/outputs/flutter-apk/app-play-release.apk `
  -FireApk build/app/outputs/flutter-apk/app-directfire-release.apk
```

## Google TV / Chromecast

Upload `build/app/outputs/bundle/playRelease/app-play-release.aab` to Play
internal testing. Download Play-generated APK from Bundle Explorer and verify
package plus certificate before rollout. Play artifact must not contain
`REQUEST_INSTALL_PACKAGES` or update `FileProvider`. Android TV uses normal Play
updates, not Play Core In-App Updates.

## Fire TV

Publish `app-directfire-release.apk` with its SHA-256. Updater checks fixed JUJO
repository, HTTPS hosts, size, digest, package, higher version code, parsed APK,
and installed signer before opening Android's user-approved installer.

## Rollback and evidence

After secure identity migration, rollback only to a bridge build that reads the
secure store. Never change package or signer. Record source commit, artifact
hashes, manifests, delivered signer, device/OS, no-data-clear upgrade, pairing,
stream with two controllers, Notification Mirror, Companion unauthorized denial,
and rollback artifact. Use exact final hashes for Play Protect/Safe Browsing
appeals.
