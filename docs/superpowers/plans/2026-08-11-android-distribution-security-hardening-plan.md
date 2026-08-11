# Android Distribution and Security Hardening Implementation Plan

**Date:** 2026-08-11

**Design:** `docs/superpowers/specs/2026-08-11-android-distribution-security-hardening-design.md`

**Scope:** Jujo.StreamClient Android builds for Google TV/Chromecast and Fire TV

**Delivery rule:** Every milestone ends with tests passing, a signed and
installable compatibility artifact, recorded hashes, and a named rollback
commit. No milestone may combine identity migration, transport migration, and
distribution separation in one release.

## Fixed Product Decisions

- Preserve package `com.vizcorp.moonlight_jujo_stream`.
- Preserve app-signing certificate SHA-256
  `EC0769DC9D131705AF4CEEA71F520F9C31482283F16A8F581937EE5E68D8E749`.
- Preserve streaming, microphone, controllers, Notification Mirror, pairings,
  settings, caches, and databases.
- Publish Google TV/Chromecast through the `play` AAB with Play-managed updates.
- Publish Fire TV through the `directFire` APK with the hardened direct updater.
- Keep streaming/native libraries identical between distribution variants.
- Do not use Play Core In-App Updates on Android TV.
- Do not remove global cleartext support until Moonlight discovery/pairing has a
  separately validated encrypted replacement.

## Release Gates Applied to Every Milestone

Before starting a milestone:

1. Confirm `git status --short` contains no unexplained changes.
2. Record the starting commit and retain the preceding signed APK.
3. Run the focused tests for the code about to change.
4. If a baseline test fails, classify and record it before editing.

Before committing a milestone:

1. Run `dart format` only on touched Dart files.
2. Run focused `flutter analyze --no-fatal-infos` on touched Dart files.
3. Run focused tests plus the full `flutter test` suite.
4. Build the appropriate release APK or both variants once flavors exist.
5. Run artifact inspection and signer verification.
6. Install/upgrade the checkpoint artifact without clearing application data.
7. Record artifact path, SHA-256, signer, device serial/model, and smoke result.

If a gate fails, fix within the current milestone or return to its starting
commit and reinstall the retained artifact. Do not advance with a known failure.

## Milestone 0: Capture the Reproducible Baseline

### Purpose

Create evidence that distinguishes pre-existing behavior from remediation
regressions and establishes the exact installed identity on both devices.

### Read-only capture

- Record `git rev-parse HEAD`, Flutter/Gradle/JDK versions, and dependency lock
  hash.
- Record current APK path, size, SHA-256, package, version code/name, signer,
  requested permissions, services, providers, and supported ABIs.
- Run `adb devices -l`; record Chromecast and Fire TV serial/model separately.
- On each device, record installed package version and signing certificate.
- Exercise upgrade without data clearing and record:
  - client certificate fingerprint;
  - paired host count and one successful connection;
  - settings and artwork cache survival;
  - one game stream with two controllers;
  - Notification Mirror modes and current peer records;
  - About/update behavior;
  - companion server startup and exposed routes.
- Capture a bounded logcat window for each scenario. Do not retain notification
  bodies, tokens, keys, or private certificates in the evidence bundle.

### Commands

```powershell
git status --short
git rev-parse HEAD
flutter --version
java -version
Get-FileHash build\app\outputs\flutter-apk\app-release.apk -Algorithm SHA256
adb devices -l
adb -d shell dumpsys package com.vizcorp.moonlight_jujo_stream
```

Use Android SDK `apksigner` and `aapt2` from the installed build-tools version:

```powershell
apksigner verify --verbose --print-certs build\app\outputs\flutter-apk\app-release.apk
aapt2 dump permissions build\app\outputs\flutter-apk\app-release.apk
aapt2 dump badging build\app\outputs\flutter-apk\app-release.apk
```

### Deliverables and gate

- Add a reusable, read-only artifact verifier at
  `scripts/verify_android_release_artifacts.ps1` in Milestone 1.
- Store the baseline report under `docs/release-evidence/android/` without
  secrets or raw unredacted logs.
- Gate: both devices stream and upgrade from the retained baseline; otherwise
  document the exact pre-existing deviation before proceeding.

### Commit

`test(android): capture distribution security baseline`

## Milestone 1: Add Guardrails Before Behavior Changes

### Files

- Add `scripts/verify_android_release_artifacts.ps1`.
- Add `test/distribution/android_artifact_contract_test.dart` for build metadata
  and provider-selection contracts that can be tested without an APK.
- Extend `.github/workflows/build-android.yml` with an initially compatible
  artifact verification job.
- Add `docs/release-evidence/android/README.md` describing redaction and the
  required evidence fields.

### Implementation

The verifier receives explicit artifact path and expected channel. It must fail
closed and return a non-zero exit code when any assertion fails. It verifies:

- package, version, signer, and ABI contract;
- presence of shared streaming, Leanback, microphone, and Notification Listener
  components;
- forbidden permission/component/string rules for `play`;
- required Fire update permission/provider rules for `directFire`;
- absence of obvious embedded private keys, access tokens, or release secrets.

At this milestone, run the verifier in `compatibility` mode against the existing
APK. Flavor-specific assertions remain tested as fixtures until Milestone 6.

### Tests and gate

- Unit-test manifest fixtures representing a valid Play artifact, valid Fire
  artifact, and each forbidden mismatch.
- Prove the verifier rejects a fixture containing
  `REQUEST_INSTALL_PACKAGES` in Play and rejects Fire without its provider.
- Build the unchanged release APK and verify its signer.

### Commit

`test(android): enforce release artifact contracts`

## Milestone 2: Introduce Typed Boundaries Without Changing Behavior

### Files

- Add `lib/bootstrap/app_bootstrap.dart`.
- Add `lib/services/update/update_provider.dart`.
- Add `lib/services/update/direct_fire_update_provider.dart` as a compatibility
  adapter over `lib/services/update/client_update_service.dart`.
- Add `lib/services/update/unsupported_update_provider.dart`.
- Update `lib/main.dart` and `lib/screens/about/about_screen.dart` to receive an
  `UpdateProvider` rather than constructing the updater.
- Add `lib/services/secure/secure_secret_store.dart` with an interface and a
  temporary compatibility implementation.
- Add fakes under `test/fakes/` and focused provider/store tests.

### Contracts

`UpdateProvider` exposes channel identity, update availability, and the actions
valid for that channel. It does not expose a universal `installApk` method.
Provider construction happens once in bootstrap and is injected into UI/state.

`SecureSecretStore` supports versioned, atomic read/write/delete operations and
distinguishes not-found, temporarily unavailable, corrupt, and permanently
invalidated results. Callers must never interpret temporary unavailability as
permission to regenerate an identity.

### Tests and gate

- Existing About/update tests must pass unchanged in user-visible behavior.
- A fake unsupported provider must expose no download/install action.
- Store tests cover atomic replacement and typed failures.
- Build one compatibility release APK, install it with `adb install -r`, and
  prove streaming, identity fingerprint, settings, and updater behavior match
  baseline.

### Commit

`refactor(android): add distribution and secret-store boundaries`

## Milestone 3: Migrate Identity and Secrets Transactionally

### Files

- Update `lib/services/crypto/client_identity.dart`.
- Add `lib/services/crypto/client_identity_store.dart`.
- Add `lib/services/crypto/client_identity_migrator.dart`.
- Add `lib/services/secure/android_secure_secret_store.dart` backed by the
  existing Android secure-storage dependency and Android Keystore.
- Add `lib/services/secure/secret_redactor.dart`.
- Update Notification Mirror token/peer persistence call sites.
- Extend `test/security/client_identity_test.dart` and add migration fault tests.

### Migration algorithm

1. Read the complete legacy identity without deleting it.
2. Validate UID, certificate, private key, algorithms, and certificate/key match.
3. Atomically write the exact bytes into the versioned secure store.
4. Read back and sign a random challenge; verify with the stored certificate.
5. Mark secure storage authoritative only after successful proof.
6. Remove plaintext private-key/token material only after the marker is durable.
7. Retain non-secret UID/public certificate fields only where compatibility
   requires them.

The migration resumes idempotently after every simulated interruption. A valid
legacy identity is never regenerated due to a locked or unavailable Keystore.
Any irreversible Keystore invalidation produces an explicit recovery screen;
it does not silently discard pairings.

### Bridge release

Build, sign, hash, and retain a bridge APK that reads both legacy and secure
formats. This APK is the only supported rollback target after migration. Record
its version and hash in release evidence.

### Tests and gate

- Byte-for-byte identity migration and certificate fingerprint preservation.
- Challenge signing after migration.
- Process interruption before write, after write, before marker, and before
  legacy cleanup.
- Secure-store unavailable/corrupt/invalidated branches.
- Log/export redaction of keys, tokens, notification bodies, and certificates.
- Upgrade both devices without clearing data; compare identity fingerprints and
  connect to every retained host.
- Build and retain the bridge APK before advancing.

### Commit

`fix(security): migrate client identity and tokens securely`

## Milestone 4: Deliver Notification Mirror Protocol v2

### Files

- Update `lib/models/notification_mirror_pairing.dart`.
- Add `lib/models/trusted_notification_peer.dart`.
- Add `lib/services/notifications/notification_peer_store.dart`.
- Add `lib/services/notifications/notification_mirror_transport.dart`.
- Update `lib/services/notifications/notification_mirror_controller.dart`.
- Update `lib/services/notifications/notification_mirror_sender.dart`.
- Update `lib/services/notifications/notification_mirror_pairing_client.dart`.
- Update `lib/services/notifications/notification_mirror_discovery_service.dart`.
- Update `lib/screens/settings/settings_screen.dart` for disclosure and peer
  reconfirmation.
- Extend notification pairing, transport, and UI tests.

### Protocol and trust behavior

- Pairing pins the peer certificate SHA-256 fingerprint and stores it securely
  with device ID, endpoint, token, capability/version, and confirmation state.
- Legacy HTTP peers migrate to `confirmationRequired`; sending remains blocked
  until the user explicitly reconfirms that device.
- Release transport uses HTTPS only, rejects redirects, validates the pin, and
  accepts only approved private LAN/ULA endpoints.
- Requests carry a bounded timestamp window and single-use nonce. Token checks
  are constant-time. Payload and header sizes are bounded.
- Serialization allowlists application ID/name, title, body, timestamp, and the
  minimum display metadata. It excludes intents, actions, extras, contacts,
  arbitrary bundles, and unsupported binary content.
- No v1 cleartext fallback exists in production.

### Prominent disclosure

Before opening Android Notification Access settings, show what data is read,
which applications are allowlisted, which paired JUJO device receives it, that
transport is encrypted, that remote storage is not used, and how to revoke it.
Require a separate affirmative action. Merely selecting Receiver/Both does not
request access.

### Tests and gate

- Correct certificate/token/nonce/timestamp succeeds once.
- Wrong certificate, redirect, replay, stale/future timestamp, public address,
  oversized request, and malformed payload fail closed.
- Legacy peers cannot receive until reconfirmed.
- Release tests prove no notification-content request uses `http://`.
- Notification Access is not opened without accepted disclosure.
- On both devices, validate off/receiver/broadcaster/both, application allowlist,
  reconnect, reboot, revoke, and peer deletion.
- Build/install a signed compatibility APK; run a full stream concurrently with
  mirrored notifications and confirm no frame/input regression.

### Commit

`fix(security): encrypt and authenticate notification mirror`

## Milestone 5: Harden the Companion Administration Surface

### Files

- Update `lib/services/companion/companion_server.dart`.
- Add `lib/services/companion/companion_access_session.dart`.
- Add `lib/services/companion/companion_authenticator.dart`.
- Add `lib/services/companion/private_interface_selector.dart`.
- Update companion settings/UI to show explicit activation, selected endpoint,
  and expiration.
- Add route, authentication, binding, expiry, and secret-redaction tests.

### Behavior

- Remove automatic TV startup. Start only through a visible, time-limited
  Companion Access session or an authenticated paired transport requirement.
- Authenticate every private route and require nonce/replay protection for
  mutations. Rate-limit failures without revealing token existence.
- Replace wildcard CORS with same-origin behavior.
- `GET /api/config` returns configured booleans, never secret values.
- Secret replacement is write-only and requires fresh authorization.
- Bind only to a selected private LAN interface; reject public, VPN, cellular,
  loopback-only fallback, and `anyIPv4` release binding.
- Bound bodies, headers, responses, idle time, and active sessions.
- Encrypt authenticated administration traffic with the device identity. Do not
  send a plaintext bearer token as a substitute for transport protection.

### Tests and gate

- Unauthenticated/expired/replayed/cross-origin requests receive generic denial.
- API key values never appear in any response or log.
- Binding-selection fixtures cover Ethernet, Wi-Fi, VPN, public, and no-valid-LAN.
- Server stops at expiry and after explicit close.
- Validate from another LAN device while proving an unpaired client cannot read
  or mutate configuration.
- Build/install a signed compatibility APK and repeat streaming/controller smoke
  tests before advancing.

### Commit

`fix(security): constrain companion administration access`

## Milestone 6: Split Play and Fire Distribution Artifacts

### Gradle and manifest files

- Update `android/app/build.gradle.kts` with the `distribution` dimension and
  `play` / `directFire` flavors. Do not add application ID suffixes.
- Keep shared capabilities in `android/app/src/main/AndroidManifest.xml`.
- Add `android/app/src/play/AndroidManifest.xml` only for Play-specific metadata.
- Add `android/app/src/directFire/AndroidManifest.xml` containing
  `REQUEST_INSTALL_PACKAGES` and the update `FileProvider`.
- Move `android/app/src/main/res/xml/update_file_paths.xml` to
  `android/app/src/directFire/res/xml/update_file_paths.xml`.

### Flutter and native files

- Add `lib/main_play.dart` and `lib/main_direct_fire.dart`; both call the shared
  bootstrap with a compile-time-owned provider.
- Add `lib/services/update/play_store_update_provider.dart`.
- Complete `lib/services/update/direct_fire_update_provider.dart`.
- Keep a fail-closed provider for unexpected/test configurations.
- Refactor `android/app/src/main/kotlin/com/limelight/jujostream/MainActivity.kt`
  to depend on a native installer bridge contract.
- Put the no-install implementation/factory in `src/play/kotlin`.
- Put the package-installer implementation/factory in `src/directFire/kotlin`.
- Ensure the Play Dart entrypoint does not import Fire updater code.

### Fire updater preflight

Retain the GitHub updater only in `directFire` and require fixed repository,
expected tag/asset format, HTTPS/no downgrade redirect, digest, expected package,
strictly higher version code, allowed ABI, valid APK signing block, and installed
signer match before Package Installer opens. Delete partial/rejected artifacts.
Request install permission only after explicit user action.

### About/update UI

- Show installed channel and version.
- Play: no download/install action; optionally open the Play listing.
- Fire: show check/download/verified/install states and actionable failures.
- Unexpected channel: no installer action.

### Build and static verification

```powershell
flutter pub get
flutter test
flutter build apk --release --flavor play -t lib/main_play.dart
flutter build appbundle --release --flavor play -t lib/main_play.dart
flutter build apk --release --flavor directFire -t lib/main_direct_fire.dart
Push-Location android
.\gradlew.bat testPlayReleaseUnitTest testDirectFireReleaseUnitTest
Pop-Location
```

Run the artifact verifier against both APKs and fail unless:

- package, version, signer, shared services, and ABIs match;
- Play contains no install permission, update provider, installer channel,
  package-archive intent, Fire repository URL, or Fire entrypoint;
- Fire contains the required provider/permission and direct updater;
- both retain Notification Listener, streaming, microphone, and Leanback support.

### Gate

- Install the Play APK locally only for pre-store smoke testing.
- Upgrade Fire TV with `directFire` without clearing data and execute one full
  verified update through Android's user-approved installer.
- Repeat identity, host pairing, settings, caches, streaming, two controllers,
  microphone, Notification Mirror, session close, and artwork checks on both.

### Commit

`feat(android): separate Play and Fire distribution channels`

## Milestone 7: Make CI and Signing Deterministic

### Files

- Update `.github/workflows/build-android.yml` to build exactly the two approved
  flavor/entrypoint pairs.
- Add CI invocations for the artifact verifier and signer comparison.
- Add release-evidence generation that records hashes and manifests without
  exposing keystore material.
- Document signing/release operations in
  `docs/release/android-distribution-runbook.md`.

### CI rules

- Reject `play` built from the Fire entrypoint and vice versa.
- Reject unsigned/debuggable release artifacts.
- Reject mismatched package, signer, version, permission, component, or ABI.
- Keep keystore, passwords, API tokens, and upload credentials exclusively in
  protected CI secrets. Never echo them.
- Publish Fire APK, checksum, and release metadata as one atomic release unit.
- Publish the Play AAB only from the protected release workflow.

### Play App Signing gate

1. Create the Play application for the existing package.
2. Enroll by securely importing the existing app-signing key; do not accept a
   new Google-generated app-signing key.
3. A separate upload key may be created and protected.
4. Upload to internal testing.
5. Download a Play-generated APK from Bundle Explorer.
6. Verify its package and certificate fingerprint against the fixed contract.
7. Stop immediately if the delivered signer differs.

### Commit

`ci(android): enforce channel-specific signed releases`

## Milestone 8: Device Qualification, Rollout, and Appeals

### Chromecast / Google TV

- Install from Play internal testing, never solely by ADB.
- Upgrade from a lower Play version code using normal Play update delivery.
- Confirm no package-install permission/capability in the delivered APK.
- Verify streaming startup/privacy gate, codec negotiation, Direct Submit,
  audio, microphone, two controllers, rumble, PiP, session close, artwork cache,
  secure Notification Mirror, and companion access.
- Run extended Tekken 8 and representative-game sessions while collecting
  bounded frames-received/rendered, decoder-drop, crash, ANR, thermal, memory,
  and input metrics. Security changes must not worsen the recorded baseline.

### Fire TV

- Upgrade the installed pre-hardening version without clearing data.
- Verify identity fingerprint, all pairings, settings, caches, and controls.
- Complete a direct update through the verified user-approved installer.
- Exercise the same streaming/game/session matrix as Chromecast.
- Prove a wrong-signer/wrong-package fixture is deleted before install UI.

### Staged release

1. Play internal track.
2. Play closed test.
3. Small staged production rollout with crash/ANR and streaming metrics watched.
4. Fire release only after the same source revision passes its matrix.
5. Halt on identity rotation, lost pairing, install capability in Play, security
   route exposure, crash/ANR regression, or material streaming/input regression.

### Appeals

After final artifacts pass:

- submit the exact Play-delivered APK hash/certificate/manifest evidence to Play
  Protect review if a warning remains;
- submit the exact Fire download URL, APK hash, signing evidence, and remediation
  summary to Safe Browsing if Chrome still blocks it;
- do not claim that a rebuild alone guarantees download reputation;
- keep the older release available until the new artifact's warnings and update
  path are verified on real devices.

### Final release record

Record source commit, version, artifact hashes, signer fingerprints, Play track,
Fire release URL, device models/OS versions, test results, known non-blocking
stream metrics, rollback artifact, and appeal case IDs.

### Commit

`docs(release): record Android security rollout evidence`

## Regression Matrix

| Domain | Automated evidence | Physical-device evidence |
| --- | --- | --- |
| App identity | package/signer/version verifier | upgrade without data clear |
| Secret migration | interruption and key-match tests | fingerprint/pairing retained |
| Play separation | forbidden manifest/code/string checks | Play-delivered APK inspection |
| Fire update | metadata/APK preflight fixtures | successful verified update |
| Notification Mirror | TLS/pin/replay/payload tests | all four modes and revocation |
| Companion access | auth/CORS/bind/expiry tests | paired access; unpaired denial |
| Streaming | existing unit/widget/integration suite | full games, codec, audio, PiP |
| Input | mapping/session regression tests | two controllers and rumble |
| Persistence | migration/store tests | settings, cache, hosts survive |
| Privacy | redaction/static scan | no desktop/secret exposure |

## Rollback Map

| Failure point | Rollback target | Data rule |
| --- | --- | --- |
| Milestones 1-2 | preceding baseline APK | no schema change |
| Identity migration | retained bridge APK | never downgrade directly past bridge |
| Notification v2 | prior bridge APK | retain v2 records; do not clear identity |
| Companion hardening | prior secure-notification APK | no secret export or plaintext fallback |
| Flavor split | last compatible signed APK per channel | same package/signer required |
| Play rollout | halt staged rollout / Play rollback | do not rotate key or package |
| Fire rollout | restore prior atomic GitHub release | do not publish mixed metadata/APK |

Rollback never re-enables cleartext notification delivery, unauthenticated
secret exposure, or a different app-signing key. If a secure protocol cannot be
repaired safely, disable only its network session while keeping streaming and
the rest of the client operational.

## Definition of Done

- Both release artifacts are built from the same approved source commit.
- Both use the existing package and signing identity.
- Play AAB/APK contains no APK installation capability or Fire updater code.
- Fire direct update validates repository, TLS path, digest, package, version,
  ABI, APK signing block, and signer before prompting the user.
- Existing client identity and pairings survive migration and every upgrade.
- Notification content and companion administration never traverse cleartext.
- Legacy Notification Mirror peers require explicit secure reconfirmation.
- No unauthenticated LAN client can retrieve or change configuration.
- No API key, private key, token, or notification body leaks through responses,
  artifacts, logs, CI, evidence, or crash diagnostics.
- Full tests, focused analysis, release builds, artifact verification, and both
  physical-device matrices pass.
- A signed functional APK exists at every milestone and its rollback procedure
  has been exercised before advancing.
