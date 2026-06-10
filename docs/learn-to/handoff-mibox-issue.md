# Handoff: MiBox 4K 2nd Gen Streaming Debug

**Date:** 2026-06-10
**Device:** Xiaomi TV Box S (2nd Gen) — codename MiTV-AFKR0 / MDZ-28-AA / jaws
**Package:** `com.vizcorp.moonlight_jujo_stream`
**ADB:** `192.168.3.240:5555`

---

## Summary

JUJO game streaming to MiBox 4K 2nd Gen showed a black screen with "stream failed". Root cause was a multi-layered failure in the Android video decoder pipeline. After extensive diagnosis, we got video working via an ImageReader fallback. Performance is still poor — a YUV→RGB optimization was just applied but **not yet tested on device**.

---

## Device Specs (relevant to JUJO)

Full reference: `Jujo.StreamServer/docs/mibox-4k-2ndgen-specs.md`

| Spec | Value |
|---|---|
| Chipset | AMlogic S905X4 |
| CPU | Quad-core Cortex-A55 @ 2.0GHz (64-bit) |
| GPU | ARM Mali-G31 MP2 |
| Codecs | AV1, VP9 Profile-2, H.265, H.264 |
| RAM | 2GB DDR3 |
| OS | Google TV (Android 11) |
| Wi-Fi | Dual-band 802.11ac |

**Critical detail:** Device reports as `android-arm` (32-bit only). No 64-bit ABI.

---

## Diagnosis Journey

### Phase 1: Symptom Analysis

**Symptom:** Server receives launch command, initializes display driver, opens game, but client shows black screen with "stream failed".

### Phase 2: Weak Device Detection Bug (FIXED)

`StreamingPlugin.kt:405-444` — `detectWeakDevice()` has a tiered detection system:

- **Tier-1:** `arm32=true || isLowRam=true` → returns true
- **Tier-2:** CAPABLE_SOC_PATTERNS match (tegra, qualcomm, snapdragon, exynos, tensor, kirin, dimensity, etc.) → returns false
- **Tier-3:** isTv + totalRamMb < 2800 → returns true
- **Tier-4:** non-TV arm64 → returns false

**Problem:** MiBox hits tier-1 (`arm32=true`) BUT:
1. The weak device H264 override only fires when `videoCodec == "auto"` — user passed `AV1` explicitly
2. The decoder map stripping to AVC-only only fires when `effectiveCodec == "H264"`
3. `supportedVideoFormats` bitmask ORs all codecs from `allSupported` even on weak devices

**Result:** Server negotiated HEVC (format=0x100) on a device whose HEVC decoder doesn't work properly.

### Phase 3: HEVC Decoder start() Failure (FIXED)

First logcat revealed: `OMX.amlogic.hevc.decoder.awesome2` — all 4 configure attempts succeed but `start()` fails with `CodecException: start failed`.

**Root cause:** Amlogic V4L2 decoder path incompatible with Flutter SurfaceProducer surface.

### Phase 4: H264 Decoder also Fails with Surface (CONFIRMED)

After fixing codec negotiation to force H264, the H264 decoder `OMX.amlogic.avc.decoder.awesome2` also fails `start()` with the Flutter surface.

### Phase 5: Null Surface Diagnostic (KEY DISCOVERY)

Added diagnostic test in `configureDecoderWithFallback()`:
- `configure(null surface)` → succeeds
- `start()` with null surface → **SUCCEEDS**
- **Conclusion:** The Amlogic decoder works perfectly in ByteBuffer mode. The Flutter SurfaceProducer's `SurfaceTexture`-backed Surface is incompatible with the Amlogic V4L2 decoder path.

### Phase 6: ImageReader Fallback (WORKING)

Implemented `ImageReader` intermediary:
1. Decoder outputs to `ImageReader.newInstance(w, h, YUV_420_888, 2)` surface
2. `renderImageReaderFrame()` acquires latest Image
3. Converts YUV→Bitmap, renders to Flutter surface via Canvas

**Result:** Video works but is extremely laggy.

### Phase 7: YUV→RGB Optimization (APPLIED, NOT YET TESTED)

Replaced JPEG encode/decode path with direct BT.601 integer conversion:
- Removed `YuvImage` → JPEG → `BitmapFactory` pipeline
- Added `yuvToBitmap()` with direct YUV planes → ARGB_8888 conversion
- Reuses Bitmap and IntArray across frames to avoid GC pressure

---

## Files Modified

### `StreamingPlugin.kt` (3 fixes)

1. **Fix A (line ~214):** Changed `weakDevice && videoCodec == "auto"` → `weakDevice` — forces H264 regardless of user codec preference
2. **Fix B (line ~237):** Changed `if (weakDevice && effectiveCodec == "H264")` → `if (weakDevice)` — strips codec map to AVC-only on all weak devices
3. **Fix C (line ~258):** Added `if (!weakDevice)` guard around `supportedVideoFormats` OR loop — weak devices only advertise their effective codec

### `VideoDecoderRenderer.kt` (major refactor)

1. **Diagnostic null-surface test** (line ~260-277): Tests if decoder works in ByteBuffer mode to isolate surface vs decoder issues
2. **Start moved into configure loop** (line ~287): `start()` now called inside the retry loop, not after it
3. **ImageReader fallback** (line ~314-353): `configureWithImageReaderFallback()` creates ImageReader and configures decoder against it
4. **All 6 render loops patched** (lines ~580-870): Each loop checks `useImageReader` flag — if true, calls `decoder.releaseOutputBuffer(idx, true)` + `renderImageReaderFrame()`
5. **`renderImageReaderFrame()`** (line ~879-901): Drains to latest Image, converts YUV→Bitmap, renders via Canvas
6. **`yuvToBitmap()`** (line ~909-984): Direct BT.601 YUV→RGB with integer math, reuses cached Bitmap and IntArray
7. **Cleanup** (line ~1204-1218): Closes ImageReader, recycles cachedBitmap, clears pixel buffer
8. **Stats** (line ~1250): Added `imageReaderMode` to stats output

---

## Testing Performed

### Logcat Captures

1. **Before any fixes:** AV1 codec forced, HEVC negotiated, all decoder `start()` calls fail
2. **After Fixes A/B/C:** H264 forced and negotiated, but H264 decoder still fails with Flutter surface
3. **After start()-in-loop fix:** All 4 format tries configure OK, all `start()` calls fail
4. **After null-surface diagnostic:** Confirmed decoder works with null surface — surface is the problem
5. **After ImageReader fallback:** Video appears! Extremely laggy due to JPEG pipeline
6. **After YUV→RGB optimization:** NOT YET TESTED ON DEVICE

### Force-Stop Testing
- Force-stopped Netflix → DRM sessions released, no change
- Force-stopped Chromecast → respawns immediately (system app), no change
- Same issue persists — not a DRM/content-protection blocking issue

### Key Logcat Facts
- `detectWeakDevice: arm32=true lowRam=false → true (tier-1)`
- `Video Codec (arg): AV1 → resolved: H264` (after fix)
- `Decoder map: {video/avc=OMX.amlogic.avc.decoder.awesome2}`
- `OMX.amlogic.hevc.decoder.awesome2` — configure OK, start() FAILS
- `OMX.amlogic.avc.decoder.awesome2` — configure OK, start() FAILS (with surface), OK (with null surface)
- Device reports: `mVideoUsedByOmx=0` (hardware NOT locked by other process)
- `4kosd set output error, newBufferCount 21 > 14` warnings during surface-mode configure
- `c2.android.avc.decoder` explicitly disabled in `/vendor/etc/media_codecs.xml`
- No C2 video decoders available — only OMX.amlogic.* HW + OMX.google.* SW

---

## What's Still Pending

### 1. Performance Testing (IMMEDIATE)
The YUV→RGB optimization was just applied. **Needs testing on device.**

Build command:
```bash
flutter build apk --debug
flutter install -d 192.168.3.240:5555 --debug
```

If still laggy, potential next steps:
- Profile the YUV→RGB conversion time via logcat
- Consider OpenGL ES rendering path (complex but fastest)
- Consider RenderScript YUV→RGB (fast, but needs Android Context injection)
- Reduce ImageReader resolution if 1080p is too heavy for ARM32

### 2. Diagnostic Code Cleanup
The null-surface diagnostic test in `configureDecoderWithFallback()` should be cleaned up for production. Currently it runs on every stream start. Options:
- Remove after confirming fix works
- Keep as debug-only flag
- Cache the result per decoder name

### 3. Other Devices Testing
Changes to StreamingPlugin.kt (Fixes A/B/C) and VideoDecoderRenderer.kt are guarded by `isWeakDevice` / `useImageReader` checks. They should not affect phones/tablets, but verify on:
- Normal phone (Qualcomm)
- Normal tablet
- Other Android TV devices

### 4. Audio Path
No changes were made to audio. Verify audio still works on MiBox.

### 5. Input/Gamepad
DualSense controller was connected during testing. Verify input still works.

---

## Relevant Files

| File | Path |
|---|---|
| StreamingPlugin.kt | `Jujo.StreamClient/android/app/src/main/kotlin/com/limelight/jujostream/native_bridge/StreamingPlugin.kt` |
| VideoDecoderRenderer.kt | `Jujo.StreamClient/android/app/src/main/kotlin/com/limelight/jujostream/native_bridge/VideoDecoderRenderer.kt` |
| CodecProbe.kt | `Jujo.StreamClient/android/app/src/main/kotlin/com/limelight/jujostream/native_bridge/CodecProbe.kt` |
| game_stream_screen.dart | `Jujo.StreamClient/lib/screens/game/game_stream_screen.dart` |
| streaming_channel.dart | `Jujo.StreamClient/lib/platform_channels/streaming_channel.dart` |
| error_codes.dart | `Jujo.StreamClient/lib/utils/error_codes.dart` |
| MiBox specs | `Jujo.StreamServer/docs/mibox-4k-2ndgen-specs.md` |

## Server Info

| Item | Value |
|---|---|
| Server IPs | 192.168.3.6, 192.168.3.30 |
| Port range | 47984/47989 |

---

## Suggested Skills

- **`diagnose`** — if performance regression needs structured debugging
- **`systematic-debugging`** — if new issues appear on other devices
- **`guide-swiftui-ui-patterns`** — not applicable (Android project)
- **`improve-codebase-architecture`** — if the ImageReader fallback pattern needs to be generalized for other SoCs
- **`ios-dev`** — not applicable

---

## Key Learnings

1. **Amlogic V4L2 decoder path** cannot accept Flutter SurfaceProducer's SurfaceTexture-backed Surface. The decoder's configure() succeeds but start() fails with CodecException. This is a firmware-level incompatibility.
2. **Amlogic decoder works perfectly in ByteBuffer mode** (null surface). The hardware itself is fine.
3. **ImageReader provides a compatible surface** for Amlogic decoders because it creates a standard BufferQueue that V4L2 can write to.
4. **The JPEG encode/decode pipeline** for YUV→Bitmap is prohibitively slow on ARM32 devices (~40-70ms per frame). Direct BT.601 conversion should be ~10-20ms.
5. **detectWeakDevice()** tier-1 fires on MiBox because it only reports 32-bit ABIs, even though the S905X4 is a 64-bit chip.
6. **Amlogic is NOT in CAPABLE_SOC_PATTERNS** — this was intentional (to catch weak Amlogic TV boxes) but means all Amlogic devices are treated as weak unless they're non-TV arm64.
