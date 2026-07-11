# Jujo StreamClient Premium Hardening Design

**Date:** 2026-07-10  
**Status:** Approved for implementation  
**Branch:** `perf/premium-ui-hardening`

## 1. Objective

Prepare Jujo StreamClient for a premium release without removing its visual
identity. Preserve trailers, parallax, focus scale, ambient audio, cinematic
moments, and rich navigation while making them deterministic, adaptive,
accessible, secure, and inexpensive on low-end Android TV hardware.

## 2. Product contracts

- Effects degrade gracefully; they are not globally removed.
- Streaming video and input remain isolated from decorative UI rebuilds.
- Cloud traffic uses normal platform certificate validation.
- Self-signed Sunshine/Apollo traffic is trusted only after pairing and only
  for the stored server certificate.
- Reduced-motion preferences from the OS override decorative movement.
- Gamepad, keyboard, touch, and assistive navigation expose the same actions.
- Background work never refreshes or rebuilds UI merely because a timer fired.
- User-facing failures are actionable; raw diagnostics remain available behind
  a secondary details action.

## 3. Architecture

### 3.1 Motion policy

Add a central motion policy derived from `ThemeProvider`, device capability,
and `MediaQuery.disableAnimations`/accessible navigation.

| Category | Normal | Reduced | Curve |
|---|---:|---:|---|
| Focus feedback | 160 ms | 0 ms | easeOutCubic |
| Micro state | 140 ms | 0 ms | easeOutCubic |
| Dialog/sheet | 220 ms | 100 ms fade | easeOutCubic |
| Page route | 260 ms | 120 ms fade | easeInOutCubic |
| Background crossfade | 300 ms | 100 ms | easeOut |

Elastic/back curves are reserved for infrequent celebration or branded
moments. Routine focus, menus, and routes use bounded curves.

### 3.2 Streaming state isolation

Move high-frequency stream statistics out of `GameStreamScreen.setState` into
a small listenable HUD model. Parse every native sample for metrics and bitrate
logic, but publish visible HUD values at a bounded cadence and only when the HUD
is enabled. Place video/platform view and HUD in separate repaint boundaries.

All connection attempts and delayed reconnects use a request generation token.
Every async continuation verifies both `mounted` and generation before changing
UI or starting a new native session.

### 3.3 Library media lifecycle

Introduce request generations for trailer initialization. A controller created
by a failed, superseded, or disposed request is always disposed. Background
selection changes are debounced outside `build` and canceled during disposal.

Replace animated full-screen runtime blur with the existing cached blur service
where supported. Animate the composed image transform/crossfade, not a live
full-screen backdrop filter. Performance mode uses reduced decode dimensions.

Achievements publish one cache update per completed batch. Automatic library
refresh becomes stale-aware and is suspended while selection is actively
changing, while pairing, or while streaming.

### 3.4 Focus, audio, and accessibility

`TvFocusable` consumes the motion policy, exposes button semantics, selected
state, enabled state, and an explicit semantic label. Existing call sites are
migrated starting with primary navigation, Library cards, PC cards, dialogs,
and streaming overlays.

UI movement audio is prewarmed and coalesced. Rapid D-pad movement produces at
most one current sound command; stale async play commands cannot restart audio.
Programmatic focus restoration does not emit a navigation sound.

### 3.5 TLS and telemetry

Remove the process-wide certificate acceptance callback. Default HTTP clients
use platform trust. Paired-server clients use the client identity context plus
explicit server-certificate verification against pairing material. A mismatch
is a hard failure with a re-pair action; it never falls back to trust-all.

Telemetry uses an asynchronous bounded queue and batched file writes. Structured
redaction covers authorization headers, cookies, tokens, certificates, email,
query parameters, and media URLs. Verbose debug capture is disabled by default
in release builds while crash/error events remain available.

### 3.6 Branded introduction and errors

The full cinematic runs on first install and after an explicitly versioned
brand reset. Later launches may skip immediately with one input. Reduced motion
shows a short static logo/fade.

Streaming errors present a localized summary, retry/back actions, and optional
technical details. Native error strings are not the primary message.

## 4. Data and lifecycle flow

1. App loads settings, accessibility state, and device capability.
2. Motion policy provides effective durations and continuous-effect allowance.
3. Library selection issues one generation-tagged background/trailer request.
4. Launch stops decorative media and refresh work before opening streaming.
5. Stream video remains stable while listenable HUD subtrees receive throttled
   statistics.
6. Disposal invalidates generations before native stop and controller cleanup.
7. Resume restarts only work still relevant to the current route and selection.

## 5. Error handling

- Async cancellation is normal and silent.
- Video fallback failure returns to static artwork without leaking controllers.
- Certificate mismatch blocks the request and guides the user to re-pair.
- Telemetry queue overflow drops oldest debug lines, never crash/error events.
- Cloud or library refresh failure keeps cached content and exposes a retry.
- Reconnect attempts are serialized and capped; delayed attempts are cancelable.

## 6. Testing and acceptance

### Automated

- Widget test proves stream-stat updates do not rebuild the video layer.
- Lifecycle tests dispose during launch, reconnect, and trailer initialization.
- Video-controller tests prove failed and superseded controllers are disposed.
- Motion tests cover normal, performance, and OS reduced-motion modes.
- Focus tests cover semantic roles, labels, selection, and rapid traversal.
- TLS tests reject unknown certificates and accept only the paired certificate.
- Telemetry tests cover redaction, queue bounds, and ordered flushing.
- Existing cloud sync suite returns green.
- Touched files pass focused `flutter analyze --no-fatal-infos`.

### Runtime

- No visible hitch while stream statistics update.
- Rapid D-pad traversal does not overlap sounds or lose focus.
- Library background changes remain smooth on performance mode.
- First and repeated launch intro behavior follows the product contract.
- Android TV, Android mobile, and Windows smoke tests complete when devices are
  available; missing hardware is reported rather than inferred as passing.

## 7. Delivery phases

1. Security and async lifecycle foundations.
2. Stream render isolation and media resource ownership.
3. Library background/refresh optimization.
4. Motion policy and route migration.
5. Focus semantics, sound coalescing, intro, and error polish.
6. Regression repair, analyzer, tests, builds, and requirement audit.

Each phase remains independently testable. Shared contracts land before their
call-site migrations, and no phase changes native streaming behavior unless its
tests cover the boundary.

## 8. Out of scope

- Removing signature visual effects.
- Replacing the native decoder/render pipeline.
- Rebranding Jujo or collapsing its launcher themes into one layout.
- Backend protocol changes unrelated to certificate verification.
