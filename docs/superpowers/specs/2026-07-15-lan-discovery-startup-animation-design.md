# LAN Discovery and Startup Animation Design

**Date:** 2026-07-15
**Status:** Pending final review
**Repositories:** `Jujo.StreamClient`, `Jujo.StreamServer`

## Objective

Make local discovery independent from Jujo Cloud and restore the existing cinematic intro on every cold application start. Add a user-facing `Cinematic / Off` preference and an extensible registry so future startup experiences do not require changes to the application bootstrap flow.

## Confirmed regressions

### LAN discovery

The Windows Server registers `_nvstream._tcp`, but publishes a TXT record whose key is empty. Android 16 receives the service and then rejects it during NSD resolution:

```text
NsdService: Invalid attribute
java.lang.IllegalArgumentException: Key cannot be empty
```

The Client therefore receives no usable resolved service. Signing in to Jujo Cloud later loads the Server from `user_server_profiles`, which makes the Server appear and hides the failed LAN discovery.

This is not a cloud-authentication or Android local-network-permission failure:

- Server and phone are on the same IPv4 subnet and communicate directly.
- The Server reports successful mDNS registration.
- Android's `RESTRICT_LOCAL_NETWORK` compatibility flag is disabled.
- The installed Client targets SDK 36, where LAN access remains implicitly granted through `INTERNET`.

### Startup cinematic

Commit `ca236f3` changed the cinematic gate from every process start to first installation only by persisting `cinematic_intro_seen_v1`. The animation component still exists and works; its bootstrap policy changed.

## Design principles

- LAN discovery must work while signed out of Jujo Cloud.
- Cloud augments local discovery; it never gates it.
- Publish standards-compliant DNS-SD records at the source instead of adding Android-specific parsing exceptions.
- Discovery owns one native session and has explicit lifecycle transitions.
- A startup animation is a registered experience selected by stable ID, not a bootstrap special case.
- Cold start and foreground resume are different events.
- Reduced-motion policy remains authoritative.
- Existing pairing, TLS pinning, and cloud merge semantics remain unchanged.

## LAN discovery design

### Server advertisement

`Jujo.StreamServer/src/platform/windows/publish.cpp` will publish one valid, non-empty TXT attribute:

```text
txtvers=1
```

The service type, instance name, hostname, and port remain unchanged. `txtvers` is compatible with DNS-SD clients and provides a stable place for future advertisement-version checks.

The TXT construction will be represented by a small helper or constants that can be tested without invoking Windows DNS registration. A regression test must fail if any advertised key is empty.

### Client resolution

`DiscoveryService` will request resolved addresses from `nsd` using `IpLookupType.any`. Usable IPv4 addresses remain preferred; loopback, IPv6 link-local, scoped, and duplicate addresses remain filtered.

Resolution order:

1. Use usable addresses returned by NSD.
2. If no address is returned, retain a valid non-loopback host supplied by NSD.
3. Do not promote loopback resolution for a remote `.local` host.
4. Preserve manual-add as the user-controlled fallback.

### Discovery lifecycle

`DiscoveryService.startDiscovery()` becomes idempotent. If a session is already active, it returns without starting another native discovery.

Lifecycle ownership moves fully into `ComputerProvider`; launcher screens no longer start discovery themselves:

- Provider initialization: start discovery immediately, even while the startup cinematic is visible.
- Resume: start or ensure discovery, then poll persisted computers.
- Pause/hidden: stop discovery and release native resources.
- Discovery error: expose a typed/structured failure to `ComputerProvider`, clear the active handle, and permit a later retry.
- Service found: resolve, normalize, deduplicate, probe, then persist.

Cloud sign-in and sign-out must not start, stop, or authorize LAN discovery. Cloud sync may merge metadata into a LAN-discovered record by UUID, certificate fingerprint, or address, without creating a duplicate card.

### Diagnostics

The Client will emit concise discovery events for:

- discovery start/stop;
- service found;
- resolved address selected;
- invalid/loopback address rejected;
- native discovery or resolution failure.

No credentials, tokens, certificates, or pairing payloads may be logged.

## Startup animation design

### Stable selection model

Introduce a startup animation ID with two initial values:

- `cinematicV1`
- `off`

Persist it under `startup_animation_id`. Missing or unknown values fall back to `cinematicV1`; unknown values are not deleted so a temporarily unavailable animation can return in a later build.

### Registry

`StartupAnimationRegistry` maps each supported ID to metadata and a builder:

- stable persisted ID;
- localized display name;
- localized description;
- widget builder.

The bootstrap gate consumes only the selected registry entry. Adding future animations requires registration and localized labels, without adding conditionals to `main.dart`.

### Cold-start behavior

The selected animation is evaluated once during creation of the root startup gate:

- `cinematicV1`: show `CinematicIntroScreen`, then enter the selected launcher mode.
- `off`: enter the selected launcher mode immediately.

Returning from background, closing a dialog, changing routes, or refreshing preferences must not replay the startup animation. A new OS process launch evaluates the preference again and replays the selected animation.

The obsolete `cinematic_intro_seen_v1` value is ignored. It may remain in preferences for compatibility; it no longer controls presentation.

### Motion and dismissal

The existing cinematic visuals and audio are preserved.

- Normal motion: play the complete cinematic.
- Reduced motion: use the current reduced-motion presentation.
- Tap, keyboard, or gamepad during the fall: advance to the impact/reveal.
- A subsequent action after reveal: dismiss.

The cinematic must not delay discovery initialization. `ComputerProvider` exists before the gate and starts discovery while the cinematic is visible, independently of cloud authentication and launcher mode.

### Settings

Add `Startup animation` under `Launcher Appearance` with:

- `Cinematic`
- `Off`

Changing the setting affects the next cold start. It does not interrupt the active screen or replay the animation immediately. The control uses the existing settings visual language and supports touch, keyboard, and gamepad focus.

## Error handling

- Invalid Server TXT data is prevented by construction and regression tests.
- A discovery startup failure releases partial native state and allows retry on resume.
- A resolved loopback address for a remote host is rejected, not contacted.
- An unknown startup animation ID safely renders `cinematicV1`.
- Animation audio failure remains non-fatal.
- Cloud unavailability does not alter LAN discovery state.

## Test strategy

### Server

- TXT advertisement keys are non-empty.
- The advertised TXT version equals `1`.
- Windows Release build compiles and packages.

### Client unit/widget tests

- NSD resolved IPv4 is preferred over hostname fallback.
- Loopback/link-local addresses are rejected.
- Repeated `startDiscovery()` creates one native session.
- Pause stops discovery; resume starts it again.
- LAN discovery runs with cloud signed out.
- Cloud merge updates an existing LAN record without duplication.
- Missing/unknown startup animation preference selects `cinematicV1`.
- `off` bypasses the cinematic.
- Cinematic appears once per root-gate lifetime and does not replay on resume.
- Settings persist both supported choices.

### Device acceptance test

1. Install the Client while preserving application data.
2. Sign out of Jujo Cloud.
3. Remove the persisted Server entry through the UI.
4. Force-stop and cold-launch the Client.
5. Confirm the cinematic appears.
6. Confirm `JulyTower` appears from LAN without cloud sign-in.
7. Confirm logcat contains a successful `_nvstream._tcp` resolution and no `Key cannot be empty` error.
8. Sign in to Jujo Cloud and confirm metadata merges into the same card.
9. Set startup animation to `Off`, force-stop, relaunch, and confirm direct entry.
10. Restore `Cinematic`, force-stop, relaunch, and confirm the cinematic returns.

## Acceptance criteria

- A Server on the same network appears without Jujo Cloud authentication.
- Android logcat contains no invalid empty TXT attribute from Jujo.Stream Server.
- LAN and cloud representations merge into one Server card.
- Existing TLS pinning and automatic cloud pairing continue to work.
- The cinematic plays on every cold start when selected.
- Foreground resume never replays the cinematic.
- The user can select `Cinematic` or `Off` in Settings.
- Future startup animations can be added through the registry without modifying bootstrap branching.

## Out of scope

- Creating additional cinematic assets or animation variants.
- Redesigning the existing cinematic sequence.
- Changing manual pairing, cloud ownership, or TLS trust policy.
- Replacing `nsd` with a different discovery library.
