# Adaptive motion and UI optimization delivery

Date: 2026-08-30
Rollback checkpoint: `d3d9b20`

## Delivered

- Added deterministic `reduced`, `constrained`, `standard`, and `premium`
  motion tiers.
- Added bounded focus, state, overlay, route, and background tokens.
- Added distinct Classic, Backbone, PS5, Hero, and Big Screen motion profiles.
- Added `MotionScope`, `AdaptiveFocusSurface`, `AdaptiveContentSwitcher`, and
  `AmbientMotionGate` as small reusable UI boundaries.
- Applied adaptive timing to all non-Classic launcher implementations. Classic
  continues through the shared app-view motion contract.
- Applied profile-aware focus to server cards, app-bar controls, Now Playing,
  PC menus, server options, and account/menu surfaces.
- Removed unconditional ornamental tickers from running-game glow, loading
  skeletons, news shimmer, Now Playing pulse, Focus Mode float/glow, particles,
  waves, tour pulse, and backdrop movement.
- Preserved a static visual equivalent whenever continuous motion is gated.
- Made Performance Mode independent from the explicit Reduce Effects setting;
  both still reduce visual cost through the resolved tier.
- Kept the selected cinematic screen on TV/constrained hardware while removing
  its parallel particles, wind, explosion, shake, and particle allocations.
- Corrected settings copy: Reduce Effects does not claim to disable previews.

## Protected feature contract

Motion tiers do not gate automatic trailers, video previews, music,
notifications, dynamic content, actions, or navigation. The video preview
scheduler remains controlled only by its functional plugin preference and
launcher state. A regression test enforces that no motion or performance policy
enters the scheduler.

## Streaming boundary

No RTSP, MediaCodec, audio, networking, input, native renderer, or server code
was changed. This delivery changes Flutter presentation policy only.

## Verification

- Focused adaptive-motion/theme/widget tests: 18 passed.
- Full Flutter suite before the final cold-start allocation refinement: 227
  passed.
- Startup regression suite after the final refinement: passed.
- `flutter analyze`: no new findings; 45 pre-existing warnings/info remain.
- Clean Play release APK: built successfully.
- Clean DirectFire release APK: built successfully.
- Package: `com.vizcorp.moonlight_jujo_stream`.
- Signer SHA-256:
  `EC0769DC9D131705AF4CEEA71F520F9C31482283F16A8F581937EE5E68D8E749`.
- Play APK SHA-256:
  `BA9A7D8D5B0364A4763FDBC5C78DA8C547E8A19F0980B08A9F203B4C681020A0`.
- DirectFire APK SHA-256:
  `E7E36232B36163E31A1E5FFCAB620AB82BF383D5551305B988234F5BF24E4043`.
- Play manifest has no `REQUEST_INSTALL_PACKAGES`.
- DirectFire manifest retains its updater permission.
- Play installed with data preservation on Chromecast HD.
- DirectFire installed with data preservation on Fire TV AFTKRT.
- Both activities launched and native bridge initialization completed.
- Final logcat: no fatal exception, ANR, or out-of-memory event.

## Runtime observations outside this change

- Chromecast cold start logged 71 and 41 skipped frames before launcher
  stabilization. Removing cinematic particle work did not eliminate them; the
  remaining signal is therefore in cold native/service initialization and must
  be profiled separately rather than guessed at in UI code.
- Both devices retain an unavailable saved host at `192.168.3.30`, producing
  periodic connection warnings. These are connectivity/state signals, not UI
  animation failures, and were not modified here.
