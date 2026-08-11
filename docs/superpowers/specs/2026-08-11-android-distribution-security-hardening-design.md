# Android Distribution and Security Hardening Design

**Date:** 2026-08-11

**Scope:** Jujo.StreamClient Android builds for Google TV/Chromecast and Fire TV

**Status:** Approved

**Decision:** One codebase and application identity, two distribution flavors,
with shared security hardening and channel-specific update mechanisms.

## Goal

Remove the concrete Play Protect and Chrome risk factors without removing
streaming, microphone passthrough, Notification Mirror, controller support, or
other client features.

The delivery must preserve:

- package name `com.vizcorp.moonlight_jujo_stream`;
- the existing app-signing certificate with SHA-256 fingerprint
  `EC0769DC9D131705AF4CEEA71F520F9C31482283F16A8F581937EE5E68D8E749`;
- installed settings, pairings, client identity, artwork caches, and database;
- identical streaming/native code in Google TV and Fire TV artifacts;
- a working, signed artifact at every delivery checkpoint.

## Confirmed Findings

The design addresses observed code and artifact behavior, not a generic
permission-reduction exercise.

1. Google documents an automatic Play Protect block for applications installed
   from Internet sideloading sources when they declare a Notification Listener.
   JUJO declares `JujoNotificationListenerService` and is currently downloaded
   directly from GitHub.
2. The current APK is a valid release artifact, and the same signing certificate
   has been used from client 1.0.0 through 1.1.23. Key rotation is not the cause.
3. Public GitHub release assets have almost no download history. Each new APK
   hash therefore has little or no Chrome download reputation.
4. `REQUEST_INSTALL_PACKAGES` was added for the direct updater in client 1.1.19.
   Google classifies it as high risk and does not accept self-update as a valid
   use for an ordinary streaming application distributed through Play.
5. Notification content is currently sent over cleartext HTTP. Receiver tokens,
   peer records, and the per-device RSA private identity are stored in ordinary
   `SharedPreferences`.
6. `CompanionServer` starts automatically on TV, binds to every IPv4 interface,
   permits wildcard CORS, and exposes unauthenticated configuration read/write
   operations. Its config response includes Steam and RAWG API keys.
7. Microsoft Defender found no threat in the exact 1.1.23 APK, and the source/APK
   audit found no SMS, Accessibility, device-admin, root, dynamic-code-loading,
   or silent-install behavior. The security exposure above is nevertheless real
   and must be fixed before an appeal.

## Distribution Architecture

### Product flavors

The Android application defines one flavor dimension, `distribution`, with two
release products:

| Flavor | Device/channel | Artifact | Update authority |
| --- | --- | --- | --- |
| `play` | Google TV / Chromecast | Android App Bundle | Google Play |
| `directFire` | Fire TV | signed universal APK | JUJO direct updater |

Both flavors use the same application ID, version name, version code, database
schema, Android namespace, and app-signing certificate. No application ID suffix
is allowed.

The existing signing key must be supplied to Play App Signing when the first
Play application is created. Google must not generate a different app-signing
key. A separate upload key may be used after enrollment. The certificate of an
APK downloaded from Play's bundle explorer must be compared with the expected
fingerprint before rollout.

Google's In-App Updates API is not used because Google officially limits it to
mobile, tablet, and ChromeOS devices; Android TV is unsupported. The `play`
flavor relies on normal Play automatic/manual updates. The About screen may open
the app's Play listing when a newer published version is known, but it never
downloads or installs an APK.

### Manifest ownership

The shared manifest contains only cross-channel capabilities. The direct update
surface moves out of `src/main` and into `src/directFire`:

- `REQUEST_INSTALL_PACKAGES`;
- update `FileProvider`;
- update file-path XML;
- native installer method-channel implementation.

The `play` merged manifest must contain none of those elements. Adding and then
removing the permission with manifest merge directives is not the primary
design; the high-risk capability must originate only in the Fire source set.

Notification Mirror, microphone, streaming, Leanback launcher, pairing service,
and render components remain shared.

### Typed update boundary

Flutter consumes an `UpdateProvider` contract instead of constructing
`ClientUpdateService` directly:

- `PlayStoreUpdateProvider` can report the installed channel and open the Play
  listing. It has no APK download/install operations.
- `DirectFireUpdateProvider` checks the allowlisted GitHub repository, downloads
  a release, verifies it, and invokes the Fire-only package installer.
- `UnsupportedUpdateProvider` is a fail-closed fallback for unexpected builds.

Each flavor has an explicit Flutter entrypoint that injects its update provider
into a shared bootstrap. The Play entrypoint never imports the Fire updater, so
tree shaking can remove its GitHub download implementation and strings. CI binds
each Gradle flavor to the only permitted entrypoint and inspects the resulting
artifact; a free-form Dart define cannot override the channel.

Native installation follows the same structure. Shared `MainActivity` depends
on an installer bridge contract, while flavor source sets provide either the
real Fire implementation or a Play no-op implementation. The Play APK therefore
contains neither package-installer intents nor dormant installation code. This
prevents building a Play manifest with a Fire updater UI or vice versa.

## Direct Fire Update Hardening

The Fire updater retains its user-facing feature but strengthens its trust
chain:

1. Accept release metadata only from the fixed JUJO repository and exact
   `client-*` tag/asset naming contract.
2. Require HTTPS and reject unexpected initial hosts, downgrade redirects,
   malformed sizes, missing digest, or version-code regressions.
3. Preserve SHA-256 verification, but do not treat a checksum hosted beside the
   APK as sufficient authenticity.
4. Before opening Package Installer, parse the downloaded APK and require:
   - the expected package name;
   - a strictly higher version code;
   - an allowed ABI set;
   - the same signer certificate as the installed application;
   - a valid APK signing block.
5. Delete partial, rejected, and superseded APK files.
6. Never request installation permission until the user explicitly selects
   Install. Never retry installation silently.

Android itself performs a signer check during update installation, but the
preflight prevents JUJO from presenting a different malicious package to the
user if the release account is compromised.

## Secure Identity Storage

The existing client certificate must not rotate during migration because it is
the pairing identity recognized by every server.

Introduce a versioned `ClientIdentityStore` abstraction backed on Android by
Keystore-protected secure storage. Migration is transactional:

1. Read and validate an existing complete identity bundle.
2. Write the exact UID, certificate, and private key to secure storage.
3. Read it back and prove the private key matches the certificate by signing and
   verifying a random challenge.
4. Switch the active store only after verification succeeds.
5. Remove plaintext private-key material. UID and public certificate may remain
   in non-secret preferences when needed for compatibility.
6. Record a schema/migration marker without logging key material.

Interrupted migration always retries from the intact source. Invalid or partial
legacy material follows the existing recovery behavior, but a valid identity is
never regenerated merely because secure storage is temporarily unavailable.

Rollback does not target the pre-migration APK directly. A retained bridge APK
understands both stores and provides the safe rollback point, preventing a
downgrade from discarding pairings.

Notification tokens and trusted-peer records move through the same secure-store
pattern. Logs, telemetry, crash reports, and exports redact tokens, private keys,
notification content, and complete certificates.

## Notification Mirror Transport

Notification Mirror remains available on both flavors, off by default.

### Consent

Before Android Notification Access settings open, JUJO presents a prominent
disclosure stating:

- which fields are read: application, title, and body;
- that access covers notifications from other applications;
- that only explicitly allowed applications are eligible;
- which paired JUJO device receives the data;
- that transport is encrypted and data is not stored remotely;
- how to disable access and remove peers.

The disclosure requires an affirmative action distinct from the Android system
grant. Selecting Receiver mode alone does not request Notification Access.

### Peer trust and TLS

Each JUJO device reuses its existing per-device RSA certificate as its local TLS
identity. Pairing creates a `TrustedNotificationPeer` containing device ID,
certificate SHA-256 fingerprint, endpoint, capabilities, and secure token.

Existing HTTP-only peers migrate to `confirmationRequired`; no notification is
sent until the user reconfirms the device. This is a one-time security migration,
not silent trust of an unauthenticated historical URL.

Notification traffic uses HTTPS with certificate pinning and no cleartext
fallback in release builds. Redirects are rejected. Peer endpoints must resolve
to private LAN/ULA addresses discovered for the approved device. Token equality
is constant-time, payload size is bounded, and requests include a timestamp and
nonce so replays can be rejected.

The payload contains only allowlisted notification fields. Icons, actions,
intents, extras, contacts, and arbitrary bundles are not serialized.

## Companion Administration Surface

The configuration server no longer starts merely because the device is a TV.
It starts only from an explicit, visible Companion Access session or when a
secure paired transport requires it.

The administrative contract is separated from notification delivery:

- public bootstrap endpoints expose only product/version and ephemeral pairing
  capabilities;
- configuration and pairing actions require an authenticated, expiring session;
- wildcard CORS is removed; same-origin requests are the default;
- request bodies, headers, and response sizes are bounded;
- state-changing requests use nonce/replay protection;
- session expiration stops administrative access and closes idle listeners;
- failed authentication is rate-limited without leaking whether a token exists.

`GET /api/config` never returns API keys. It returns only redacted status such as
`steam_api_key_configured: true`. Secret replacement is write-only, requires
fresh authorization, and cannot recover the prior secret.

The server binds only to the selected private LAN interface. It does not fall
back to mobile, public, VPN, or arbitrary interfaces. The app shows the active
interface, endpoint, and session expiration to the user.

The final transport must provide cryptographic protection for administrative
traffic. The implementation may use the device TLS certificate for native
companion clients. If the embedded browser UI remains supported, its explicit
pairing flow must establish an encrypted authenticated session before any
configuration data is exchanged; plaintext bearer tokens are not acceptable.

## Network Policy

The global `usesCleartextTraffic=true` cannot simply be removed because Moonlight
discovery/pairing and local host protocols currently use HTTP on raw LAN
addresses. That change is outside this remediation and would risk streaming.

Instead:

- sensitive notification and administrative traffic becomes encrypted;
- unrelated metadata URLs continue to be upgraded to HTTPS where possible;
- cleartext use is inventoried and covered by tests;
- no private data is allowed through an unclassified cleartext call site.

This preserves streaming compatibility without treating global cleartext as
permission to send sensitive data insecurely.

## Delivery Sequence

Every milestone ends with both flavors buildable and the preceding known-good
artifacts retained.

1. **Baseline and guardrails**
   - Record hashes, signer, merged manifest, installed-data smoke test, stream
     metrics, and Notification Mirror behavior on both devices.
   - Add artifact-inspection tests before changing manifests.
2. **Boundaries without behavior change**
   - Add distribution/update and secure-store interfaces.
   - Route current behavior through them while producing one compatibility build.
3. **Identity and token migration bridge**
   - Migrate secrets transactionally; prove no certificate or pairing changes.
   - Retain a signed bridge APK as the rollback target.
4. **Secure Notification Mirror v2**
   - Add disclosure, peer reconfirmation, pinned TLS, replay protection, and
     removal of release cleartext fallback.
5. **Companion surface hardening**
   - Make access explicit and time-bound, authenticate every private route,
     redact secrets, constrain binding, and remove wildcard CORS.
6. **Flavor separation**
   - Move Fire installer assets to `directFire`; implement typed update providers;
     build and inspect `playRelease` and `directFireRelease`.
7. **Store and device validation**
   - Enroll the existing signing key in Play App Signing.
   - Test Play-delivered artifacts through an internal track on Chromecast.
   - Test clean install and upgrade on Fire TV using the direct artifact.
8. **Release and appeal**
   - Roll out Play using internal, closed, and staged production tracks.
   - Publish the Fire APK and signed checksums.
   - Submit the exact release hash and evidence in Play Protect/Safe Browsing
     appeals after hardening, not before.

## Rollback Strategy

- Each milestone is a self-contained commit with tests and signed artifacts.
- Database and preference schemas are additive and versioned.
- The app-signing key, package name, native streaming libraries, codec policy,
  controller path, and renderer selection are unchanged.
- Protocol v2 can be exercised behind an internal build flag during validation,
  but production never silently downgrades sensitive traffic to v1.
- The identity bridge APK is the rollback destination after secret migration.
- Play staged rollout is halted on security, crash, pairing, rendering, or input
  regression; the last Play artifact remains available for rollback.
- Fire release publication is atomic: APK, checksum, metadata, and release notes
  are promoted together only after verification.

## Verification Matrix

### Static artifact checks

- Both artifacts have the expected package, version, and signer.
- `playRelease` has no `REQUEST_INSTALL_PACKAGES`, update provider, installer
  method channel, package-archive intent, Fire updater repository URL, or Fire
  updater entrypoint.
- `directFireRelease` contains the installer capability and no Play-only update
  dependency.
- Both contain Notification Listener, microphone, streaming service, Leanback
  launcher, and the expected ARM ABIs.
- No private key, token, API key, or release credential appears in the APK as a
  hardcoded value.

### Security tests

- Legacy identity migrates byte-for-byte and signs with the same key.
- Interrupted migration resumes without generating a new identity.
- Wrong certificate, token, nonce, timestamp, public address, redirect, and
  oversized payload are rejected.
- Unauthenticated config reads/writes return a generic denial.
- Config responses never return stored API-key values.
- Notification content cannot traverse HTTP in a release build.
- Existing peers require explicit reconfirmation before v2 traffic.
- A downloaded Fire update with wrong package, signer, version, ABI, hash, or
  signing block is deleted and never reaches Package Installer.

### Functional regression tests

- Existing host pairings and cloud certificate pins survive upgrade.
- Streaming startup, codec negotiation, Direct Submit, audio, microphone,
  controllers, rumble, PiP, session close, artwork cache, and launch privacy gate
  behave identically in both flavors.
- Notification Mirror off/receiver/broadcaster/both modes still work after secure
  pairing and respect application allowlists.
- About/update UI displays the correct channel and never exposes a Fire action
  in the Play flavor.

### Device validation

On Chromecast/Google TV:

- install through the Play internal track, not only ADB;
- verify the delivered certificate and merged manifest;
- verify automatic/manual Play update from a lower version code;
- run a full game stream with two controllers and Notification Mirror.

On Fire TV:

- upgrade the installed pre-hardening build without clearing data;
- prove pairing identity, settings, caches, and controls remain intact;
- perform a verified direct update through the user-approved installer;
- run the same streaming and Notification Mirror scenarios.

## Acceptance Criteria

- No feature listed in the goal is removed on either device family.
- Google TV installs through Play and contains no package-install capability.
- Fire TV retains a functioning, user-approved direct updater with signer
  preflight.
- Both variants use the expected package and app-signing certificate.
- No valid existing client identity is rotated or regenerated during migration.
- Notification content and administration data never use cleartext transport.
- No unauthenticated LAN client can read or change JUJO configuration.
- No endpoint returns stored API keys or private identity material.
- All focused tests, static artifact checks, Flutter analysis of touched files,
  release builds, and device smoke tests pass before publication.
- Play Protect and Chrome appeals contain the exact final artifact hash and
  evidence; no claim promises that code changes alone can manufacture download
  reputation.

## Non-goals

- Removing Notification Mirror, microphone passthrough, direct Fire updates, or
  other product functionality.
- Replacing Moonlight HTTP discovery/pairing in this remediation.
- Changing streaming, decoder, controller, or game-launch behavior without a
  separately reproduced defect.
- Changing package name or rotating the established app-signing key.
- Disabling Play Protect, instructing users to bypass warnings, or using heavier
  obfuscation to evade analysis.

## Primary References

- Play Protect warning guidance:
  https://developers.google.com/android/play-protect/warning-dev-guidance
- `REQUEST_INSTALL_PACKAGES` policy:
  https://support.google.com/googleplay/android-developer/answer/12085295
- Mobile Unwanted Software policy:
  https://developers.google.com/android/play-protect/mobile-unwanted-software
- Google Play App Signing:
  https://support.google.com/googleplay/android-developer/answer/9842756
- Android app update identity rules:
  https://developer.android.com/google/play/app-updates
- In-App Updates supported device classes:
  https://developer.android.com/guide/playcore/in-app-updates
