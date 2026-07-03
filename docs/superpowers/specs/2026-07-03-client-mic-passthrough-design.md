# Client Microphone Passthrough (classic protocol) — Design

Date: 2026-07-03
Branch: `feature/client-mic` (both StreamClient and StreamServer, cut from `master`)
Transport decision: **Route A — tunnel over the existing encrypted control channel** (not a new RTP stream).

## Problem

The microphone feature is fully built **only for the WebRTC (browser) client**. The Flutter
client — the one running on the MiBox, i.e. the real product — uses the classic Moonlight
protocol, which has **no client→server audio path**. Today only the "shell" exists:

- Client: a Settings toggle (`clientMic`, default ON) that sends `clientMic=1` on the REST
  `/launch` and `/resume` requests. No native capture, no upstream transport.
- Server: parses `clientMic` → `session.client_mic` → sets `config.audio.flags[CLIENT_MIC]`,
  but **nothing consumes that flag** on the classic path. The `virtual_mic_t` device and the
  `enable_client_mic` / `client_mic_device_name` config already exist and are used by WebRTC.

So ~30% (the sink + config + REST flag) is done; the missing 70% is capture + transport +
server receive on the classic protocol.

## Data path (end to end)

```
Android AudioRecord (48 kHz, mono, 20 ms / 960 samples)
  → Opus encode (existing libopus.a — full build, encoder + decoder)
  → moonlight-common-c: NEW control packet 0x3003 "Client Mic Data" (Jujo extension)
     sent over the already-encrypted, already-connected ENet control stream
  → server stream.cpp: server->map(IDX_CLIENT_MIC_DATA, handler)
  → Opus decode → virtual_mic->push(samples, 48000, channels, frames)   ← SAME sink as WebRTC
  → the game reads "Jujo Stream Mic In"
```

## Why the control channel (Route A)

The control stream is already bidirectional (client input travels client→server over it today),
already encrypted, and already has a message dispatch loop on both ends. So there is **no new UDP
port, no new crypto handshake, no new RTP stack** — the smallest new "cable" that actually reaches.
It is a reliable-ordered channel: fine for voice / push-to-talk; under packet loss it adds
retransmit latency instead of dropping. If realtime latency later matters, migrate to an unreliable
RTP stream (Route B) behind the same capture + `virtual_mic` ends. Marked in code with a
`// ponytail:` comment naming that upgrade path.

## Packet format

Control packet type `0x3003` (next free Jujo extension after `0x3000`–`0x3002`).
Payload after the 2-byte type header = **one raw Opus frame** (bytes). ENet frames each packet,
so no explicit length prefix is needed. Fixed negotiated format: **48 kHz, mono, 20 ms**.

`// ponytail: mono/48k/20ms fixed; per-frame config negotiation only if a client needs it.`

## Server pieces (StreamServer)

1. `stream.cpp`: add `#define IDX_CLIENT_MIC_DATA 19` and `0x3003` to `packetTypes[]`.
2. `session_t`: add `std::shared_ptr<platf::virtual_mic_t> virtual_mic` and an `OpusDecoder*`
   (or a tiny mic-decoder holder) per session.
3. New handler registered via `server->map(packetTypes[IDX_CLIENT_MIC_DATA], ...)`:
   - Gate: only if `config::audio.enable_client_mic` **and** the session's `CLIENT_MIC` flag.
   - **Lazily create** `virtual_mic` + `OpusDecoder` on the first mic frame (mirror
     `webrtc_stream.cpp:4601` which calls `audio_ctx->control->virtual_microphone(name,2,48000,960)`).
   - Decode Opus → `virtual_mic->push(...)`.
4. Teardown: release `virtual_mic` + decoder on session end.
5. **No new config** — reuse `enable_client_mic` + `client_mic_device_name`.

Server-side self-check: feed known Opus frames to the handler and assert the `virtual_mic`
receives the expected PCM length/rate.

## Client pieces (StreamClient — Android first; MiBox is the target)

1. Native `AudioRecord` capture thread (48 kHz mono 16-bit), `RECORD_AUDIO` permission
   (manifest + runtime request).
2. Opus encode using the already-linked `libopus.a` (`opus_encoder_create` / `opus_encode`).
3. moonlight-common-c fork: expose a `LiSendMicPacket`-style API that emits `0x3003` over the
   control stream; wire it through `bridge/moonlight_bridge.c` and a method-channel/JNI call
   from Dart to start/stop capture.
4. Dart: when `clientMic` is ON and a stream starts → request permission + start capture; stop
   on teardown. **Reuse the existing toggle** (`StreamConfiguration.clientMic`).
5. Fix the now-stale comment/string in `stream_configuration.dart`
   ("only effective in WebRTC mode") — it works on classic after this.

## Scope discipline (deliberate, lazy-but-correct)

- **Android only first.** iOS / macOS / Windows capture is a later follow-up against the same
  `0x3003` contract.
- Mono / 48 kHz / 20 ms / reliable channel. No jitter buffer, no loss concealment, no per-frame
  config negotiation.
- Reuse `virtual_mic`, `enable_client_mic`, `client_mic_device_name`, and the REST `clientMic`
  flag as-is. No new config keys, no new ports.

## Verification

1. Server self-check (above).
2. End-to-end on MiBox: talk → the host's "Jujo Stream Mic In" device shows input (verify in
   Audacity or a voice app on the host).
3. `flutter analyze` clean; release APK builds with the SUPABASE dart-defines.

## Out of scope

- Non-Android capture platforms (later).
- Unreliable/RTP transport (Route B — only if voice latency proves inadequate).
- Mic level / gain UI, device selection on the client (later if wanted).
