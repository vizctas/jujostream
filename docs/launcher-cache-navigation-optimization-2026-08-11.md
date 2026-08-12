# Launcher cache and navigation optimization

Date: 2026-08-11

## Result

The launcher now keeps a warm library, refreshes stale server state in place,
limits artwork decode pressure, and does not show artwork-download progress for
automatic catalog work. Manual metadata or artwork refreshes retain explicit
progress feedback.

No streaming, decoder, controller, session-launch, or security-flavor behavior
was changed by this delivery.

## Confirmed causes

1. Launcher entry and post-stream return could destructively reload the app
   list, temporarily discarding valid in-memory content.
2. Catalog freshness and metadata freshness had no single owner, so automatic
   work could run more often than needed.
3. Focus changes queued more poster and backdrop decodes than the user could
   consume; obsolete requests were not coalesced.
4. Some themes did not supply stable artwork cache keys and Big Screen decoded
   every poster at an unnecessarily large width.
5. Oversized off-screen cache extents caused excessive widget and image work.
6. Big Screen propagated every intermediate selection immediately, causing
   redundant parent rebuilds.
7. The progress pill treated normal catalog I/O as artwork enrichment, so even
   a warm launcher falsely appeared to download all images again.

## Changes

### Warm library and stale-while-revalidate

- Added `LibraryFreshnessPolicy` with a 30-second catalog TTL and 24-hour
  metadata TTL.
- Added `AppListProvider.loadForLauncher()`.
- Restores the persisted app list before contacting the host on a cold process.
- Keeps the current list visible during stale refreshes.
- Avoids network work on fresh same-server re-entry.
- Reconciles running-game state after streaming without clearing the launcher.
- Keeps full-list removal authoritative while preserving the known single-app
  busy-session response.
- Provider now owns per-server library and metadata refresh timestamps.
- Automatic enrichment is silent. User-requested enrichment remains visible.

### Bounded artwork pipeline

- Added `LatestWindowScheduler`: two concurrent poster operations and one
  concurrent backdrop operation.
- New focus replaces obsolete pending work; active operations finish safely.
- Poster prefetch uses a seven-item directional window.
- Backdrop requests are debounced and use the actual selected backdrop policy.
- Added per-theme decode budgets and reduced Big Screen poster decoding from
  960 px for every item to 320 px unselected and 640 px selected.
- Added stable cache keys to Backbone, Big Screen, Hero, and PS5 artwork.
- Reduced game-list off-screen cache extents from 1200-1600 px to 600-800 px.
- Coalesced Big Screen parent selection propagation to 180 ms.

### Progress semantics

- `showsForegroundProgress` now represents only explicit metadata/artwork work.
- Automatic catalog refresh and warm re-entry no longer display the
  `Downloading art & data` pill.
- Android enrichment notifications remain limited to manual work.

## Regression coverage

- Complete host lists remove stale cached entries.
- Busy-session single-app responses preserve the complete catalog.
- Same-server warm re-entry performs no fresh request inside the TTL.
- Forced refresh still reconciles running state.
- Persisted content becomes visible before a blocked network response.
- Stale refresh never emits an empty catalog frame.
- Catalog loading cannot activate artwork progress.
- Scheduler concurrency and latest-window coalescing are deterministic.
- Artwork decode budgets and theme cache-key contracts are tested.

Verification completed:

- Focused launcher suite: 28 tests passed.
- Full Flutter suite: 213 tests passed before the final progress regression;
  the added regression then passed in the focused suite.
- Targeted Flutter analyzer: no issues.
- Release build: successful after `flutter clean` and dependency restoration.
- APK Signature Scheme v2: verified.

## Fire TV live validation

Device: `AFTKRT`, ADB `192.168.3.137:5555`.

- Installed with `adb install -r`; application data preserved.
- Package resumed normally as `MainActivity`.
- Warm launcher re-entry displayed backdrop and visible poster window
  immediately, without the artwork progress pill.
- Eighteen rapid right-navigation events ended with selected and neighboring
  art rendered.
- Final navigation log contained no crash, ANR, OOM, or skipped-frame event.
- Zero active JUJO notifications after the test.

## APK

- Flavor: `directFire`
- Package: `com.vizcorp.moonlight_jujo_stream`
- Version: `1.1.23` (`versionCode 24`)
- Min/target SDK: 24/36
- Size: `102489030` bytes
- SHA-256: `7C08ACD50ADB2F1ACEB3925833233647554D37DB7EE44E95FB61E047F9198C0F`
- Signer certificate SHA-256:
  `ec0769dc9d131705af4ceea71f520f9c31482283f16a8f581937ee5e68d8e749`
- Output: `build/app/outputs/flutter-apk/app-directfire-release.apk`

## Device coverage limitation

Chromecast was not visible in `adb devices -l` or ADB mDNS during this delivery,
so this exact build could not be installed or validated there. Fire TV is the
only device for which installation and live launcher behavior are claimed.

## Non-regression contracts

- Never clear a valid launcher catalog before replacement data exists.
- Keep library freshness and metadata freshness separate.
- Automatic work must be silent and bounded.
- Manual work may expose progress and notifications.
- Every remote artwork request must use a stable logical cache key and a decode
  size appropriate to its rendered dimensions.
- Selection changes may replace pending artwork work; they must not accumulate
  an unbounded decode queue.
- Release acceptance requires installing the exact clean-built APK and checking
  its hash plus device behavior, not relying only on Gradle success output.
