# Streaming Pipeline Hardening Design

Date: 2026-08-17

## Objective

Reduce latency, frame drops, audio discontinuities, and unrecoverable stalls without changing known-good capture, encoder, FEC, or default rendering behavior unless a deterministic test proves the replacement.

## Non-negotiable invariants

1. At most one Moonlight native connection may be starting or active.
2. A new connection cannot start until the prior `LiStartConnection()` has returned and teardown has completed.
3. A renderer may only count a frame as submitted to a valid Surface generation.
4. A destroyed DirectSubmit Surface must produce one recoverable session event; it cannot fail silently.
5. Explicit codec selection advertises only that codec. Automatic selection may advertise multiple verified codecs.
6. Weak-device safety policy applies consistently to automatic and explicit negotiation.
7. Audio queues remain bounded, observable, and thread-safe. Overflow cannot let producer and consumer race on the same PCM region.
8. Exactly one bitrate controller owns adaptation. Server ABR disables reconnect-based client ABR.
9. Queue overflow or decoder recovery failure must escalate deterministically instead of leaving a live-but-dead stream.
10. All new behavior remains behind narrow components with unit-testable contracts.

## Components

### Client lifecycle

`NativeStreamLifecycle` owns `IDLE`, `STARTING`, `ACTIVE`, `INTERRUPTING`, and `STOPPING`. Start, timeout, termination, and user stop are serialized. A timeout interrupts startup, waits for its thread, then performs normal cleanup.

### Codec policy

`CodecAdvertisementPolicy` receives requested codec, weak-device status, and probed decoders. It returns the effective codec, decoder map, and exact protocol mask. No negotiation logic remains embedded in `StreamingPlugin`.

### Render health

Surface callbacks carry monotonically increasing generations. `StreamingPlugin` watches startup output and steady-state progress separately. Recovery is re-armed after progress. Failed local recovery emits `renderStalled`, causing one serialized reconnect.

### Audio

Oboe uses a bounded SPSC FIFO whose producer never mutates the consumer cursor. Overflow and underrun counters are exported. AudioTrack remains a compatibility fallback and must handle partial and negative writes correctly.

### Congestion control

Classic loss reports feed server ABR. Each encoder starts from its own requested bitrate and is capped by its own original bitrate. Bitrate-only NVENC reconfiguration does not force IDR. Server advertises ABR ownership; client controller stands down when advertised.

### Telemetry

Expose native video queue depth, Surface generation/validity, renderer recovery state, audio FIFO occupancy/underruns/overflows, requested bitrate, and host/network/decode timing fields already present in the protocol.

## Rollout safety

- Preserve DirectSubmit default-off behavior.
- Preserve weak-device latency pacing and low-latency-frame-balance policy.
- Preserve latest-frame capture, no-B-frame encoder configuration, one-frame VBV, and 20 percent FEC.
- Keep server ABR default-off until hardware validation.
- Do not change 1 Gbps intra-frame pacing globally without device/network A/B evidence.

## Verification

- Unit tests for lifecycle transitions, codec masks, watchdog re-arming, SPSC overflow behavior, ABR initialization/caps, and server/client ownership.
- Existing Flutter, Android, and server test suites.
- Release APK build for supported product flavors.
- Server build or focused compilation tests available in the checkout.
- Hardware acceptance remains pending while ADB is unavailable: FireTV, Chromecast, and MiBox long sessions; two controllers; repeated start/stop; Surface recreation; network loss/jitter.

## Rollback

Both repositories are tagged `checkpoint/pre-streaming-peak-20260817`. The tag is immutable unless explicitly deleted. Reverting future commits or creating a recovery branch from the tag restores the pre-hardening state without `reset --hard`.
