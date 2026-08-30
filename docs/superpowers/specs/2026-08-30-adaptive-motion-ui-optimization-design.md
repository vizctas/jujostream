# Adaptive motion and UI optimization design

Date: 2026-08-30
Status: implemented

## Objective

Polish JUJO's existing interface without redesigning its layouts, identity, five
launcher themes, or behavior. Make focus and navigation responsive on every
device, preserve each launcher's personality, and prevent decorative animation
from competing with artwork, video previews, or streaming.

## Confirmed problems

1. Motion rules are fragmented: most animated surfaces declare local durations
   and curves while only a small subset consumes `MotionPolicy`.
2. Continuous effects use unrelated lifetime and gating rules. Several tickers
   can run together or continue when their surface is not useful.
3. Device class is used as a coarse performance proxy in places where a stable
   capability budget is required.
4. Rapid D-pad input can enqueue visual work and trigger layout-affecting
   transitions instead of replacing the previous visual state.
5. The five launcher personalities have no typed motion contract, so their
   differences are expressed through scattered constants.

## Non-negotiable feature invariant

Adaptive degradation changes ornament only. It never disables user-enabled
features or content. Automatic trailers, video previews, music, dynamic
banners, notifications, actions, overlays, and navigation remain functional in
every profile. A constrained device may receive a short crossfade around a
trailer, but the trailer itself still starts when its preference is enabled.

## Architecture

### 1. Capability tiers

`MotionTier` has four deterministic levels:

- `reduced`: system accessibility or explicit reduced-effects preference.
- `constrained`: Performance Mode or a conservative device capability.
- `standard`: normal complete motion with one ambient effect at a time.
- `premium`: full launcher personality within the same frame-safe limits.

Precedence is accessibility, user Performance Mode, device capability, then
launcher personality. The tier is stable during an interaction. Resolution
failure falls back to `constrained`, never to the most expensive profile.

### 2. Motion tokens

`MotionTokens` owns named focus, state, overlay, route, and background timings,
plus enter, exit, state, and focus curves. Routine interactions do not use
bounce or elastic curves. Frequently repeated movement is limited to opacity
and transforms.

Expected ranges:

- focus: 100-160 ms
- state: 120-180 ms
- overlay: 180-280 ms
- route: 220-320 ms
- reduced: immediate change or 80-100 ms opacity crossfade

### 3. Launcher personalities

`LauncherMotionProfile` varies expression without overriding accessibility or
performance limits:

- Classic: direct crossfade and at most 1-2 percent focus scale.
- Backbone: crisp focus, subtle lift, 2-4 px maximum travel.
- PS5: soft spatial crossfade with 8-12 px directional travel.
- Hero: artwork-led depth and restrained ambient motion.
- Big Screen: loud D-pad focus and at most 1.025 scale.

### 4. Delivery boundary

`MotionScope` exposes the resolved policy without enlarging `ThemeProvider`.
Small reusable primitives own focus transitions, content switches, route
transitions, and ambient gating. Existing screens migrate incrementally; large
screens are only extracted where touched behavior gains a clear boundary.

## Migration order

1. Typed capability, tokens, personality profile, scope, and tests.
2. Shared focus and ambient primitives.
3. Launcher and primary PC/server navigation.
4. Dialogs, settings, onboarding, notification/news/media overlays.
5. One-shot branded and cinematic animation.

## Continuous effect rules

- A ticker runs only while its surface is mounted, visible, and permitted.
- `reduced` and `constrained` do not run ornamental loops.
- `standard` permits at most one expensive ambient treatment per visible
  composition.
- Rapid navigation replaces in-flight visual state; it does not queue motion.
- Pausing decoration must not pause media or alter a functional preference.

## Failure behavior

- Unknown capability resolves to `constrained` with all features intact.
- Missing scope resolves to a safe standard policy.
- Reduced-motion state changes are applied without replaying entrances.
- An animation failure leaves final content visible and interactive.

## Verification

- Unit tests cover tier precedence, tokens, personalities, and safe fallback.
- Widget tests cover reduced motion, Performance Mode, rapid focus changes,
  ticker pause/disposal, and enabled trailer preservation.
- Static analysis and existing Flutter tests must pass.
- Android APKs are built from a clean checkpoint.
- When ADB devices are available, install on Chromecast and Fire TV and inspect
  startup, launcher, focus, previews, and runtime errors.

## Non-goals

- Redesigning layouts or changing visual identity.
- Removing or simplifying functional features.
- Modifying RTSP, MediaCodec, audio, networking, or server behavior.
- Broad refactors unrelated to motion, focus, accessibility, or render cost.
