# Premium Client Hardening Implementation Plan

**Design:** `docs/superpowers/specs/2026-07-10-premium-client-hardening-design.md`
**Branch:** `perf/premium-ui-hardening`

## Phase 1: Shared contracts

1. Add `MotionPolicy` with normal, reduced, and performance behavior.
2. Wire OS reduced-motion state into Library, focus wrappers, routes, and intro.
3. Add focused unit/widget coverage for policy values.

## Phase 2: Async and media ownership

1. Add generation/cancellation guards to stream launch and reconnect paths.
2. Fix AppView navigation after async profile recording.
3. Make trailer attempts dispose failed and superseded controllers.
4. Cancel background debounce and media requests during disposal.
5. Add lifecycle and ownership regression tests where platform interfaces permit.

## Phase 3: Streaming render isolation

1. Extract visible stream statistics into a listenable model.
2. Throttle HUD publication while preserving raw samples for metrics/ABR.
3. Rebuild only the HUD subtree and isolate the video layer for painting.
4. Serialize delayed reconnects and overlay transition timers.

## Phase 4: Library resource optimization

1. Batch achievement cache publication.
2. Make refresh stale-aware and suspend it during active interaction/streaming.
3. Move background/media side effects out of `build`.
4. Prefer cached/static blur composition and retain graceful fallback.

## Phase 5: Premium interaction polish

1. Replace routine elastic/back curves with bounded motion-policy transitions.
2. Reduce the Library-to-stream route latency.
3. Coalesce UI focus sounds and suppress programmatic restoration sounds.
4. Add semantics to shared focus controls and primary navigation call sites.
5. Make the cinematic full-length only on first/versioned presentation.
6. Localize friendly stream error summaries and separate technical details.

## Phase 6: Network and telemetry hardening

1. Inventory all HTTP client creation and classify cloud versus paired-server use.
2. Remove the process-wide trust-all callback.
3. Add a paired-server client factory with stored-certificate verification.
4. Route cloud/metadata clients through platform trust.
5. Replace synchronous debug-log writes with a bounded asynchronous queue.
6. Expand structured redaction and disable verbose capture in release mode.

## Phase 7: Release verification

1. Restore cloud-sync tests or document a separate pre-existing product defect.
2. Run focused analyzer on every touched file.
3. Run full Flutter tests.
4. Build Windows debug and Android debug artifacts.
5. Run available desktop smoke checks; record missing physical-device evidence.
6. Audit every design acceptance criterion against code and command evidence.

## Commit boundaries

- `docs`: design and implementation plan
- `fix(lifecycle)`: async and media ownership
- `perf(stream)`: isolate high-frequency statistics
- `perf(library)`: batch and cache decorative work
- `refactor(motion)`: centralize adaptive movement
- `fix(a11y)`: semantics and focus feedback
- `fix(security)`: scope TLS trust and telemetry
- `test`: regression and release verification repairs
