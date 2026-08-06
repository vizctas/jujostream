# Private Game Launch Session Design

**Date:** 2026-08-06

**Scope:** Jujo.StreamServer and Jujo.StreamClient

**Status:** Approved

**Decision:** Stateful host readiness plus a client-side privacy gate

## Goal

Deliver a console-style launch and teardown flow for every non-Desktop app:

- Never expose the Windows desktop while a game is launching.
- Detect the actual game process and window instead of trusting the launcher.
- Restore, foreground, and validate the game window before revealing video.
- Close the processes owned by the launched game when the user closes the
  session, including Steam shortcut games installed outside `steamapps/common`.
- Present cached game artwork correctly while launch and RTSP initialization
  are in progress.
- Reveal the ready game through a selectable premium transition.

The existing Desktop entry is explicitly exempt and continues to reveal the
captured display as soon as the transport is ready.

## Confirmed Failure Chain

This design is based on code and live host logs, not timing assumptions.

### Launch and focus

- Generic command and `steam://rungameid/...` launches return from
  `proc_t::execute()` without finding or focusing the resulting game window.
- The robust Win32 focus loop currently exists only inside the Playnite helper.
- `/launch` raises the RTSP launch session immediately after `execute()`.
- In the 2026-08-06 TEKKEN trace, RTSP negotiation began about 0.5 seconds after
  dispatching the Steam URI. That is far earlier than the game window can be
  considered ready.
- The client removes its loading overlay when native transport startup returns,
  not when the host game is foreground and stable.

### Steam teardown

- Steam reparents a launched game outside the server's process group.
- TEKKEN is configured with shortcut ID `14390411998296801280` and working
  directory `G:\\Games\\TEKKEN 8\\Polaris\\Binaries\\Win64`.
- That shortcut ID has no regular Steam app manifest to resolve.
- The existing safety check accepts only roots under `steamapps/common`, so it
  rejects the configured TEKKEN directory.
- The live log consequently reports that no install directory was resolved and
  skips cleanup. The Steam client is not the process that should be killed.

### Artwork and cache

- A portrait poster fallback is rendered into a 16:9 background using
  `BoxFit.cover`, cropping it to a zoomed central slice.
- Both launch overlays use `Image.network` instead of the persistent game-art
  cache, causing fresh network work during repeated launches.
- Normal library poster call sites already use deterministic app/role cache
  keys and a 90-day disk cache; the launch path bypasses that contract.

## Architecture

The solution has four cooperating boundaries:

1. A Windows `GameSessionOrchestrator` owns launch discovery, focus, readiness,
   and teardown state.
2. A paired-client launch-state endpoint publishes an immutable session
   snapshot without blocking HTTPS or RTSP worker threads.
3. The client maintains a native and Flutter privacy gate until host readiness
   and a post-readiness video frame are both proven.
4. One cached `LaunchExperience` renders game art, progress, errors, and the
   selected reveal effect across both `/launch` and RTSP startup.

## Server Session Orchestrator

### State model

Each non-Desktop launch owns a typed state machine:

```text
idle
  -> launching
  -> waitingWindow
  -> focusing
  -> stabilizing
  -> ready

Any active state -> failed | cancelling
cancelling -> closed
```

The snapshot contains:

- opaque launch-state token;
- app ID and UUID;
- owning client identity;
- state and stable machine-readable failure code;
- human-readable progress detail;
- attempt counter;
- readiness generation;
- selected process ID and window identity for diagnostics only;
- monotonic timestamps for launch, candidate discovery, and readiness.

Snapshot reads never invoke process cleanup, display reconfiguration, or other
lock-taking side effects.

### Worker lifetime

- The orchestrator runs on its own cancellable worker.
- `/launch` dispatches the app and returns normally; it does not wait up to 90
  seconds on an HTTPS thread.
- Starting a replacement app cancels and joins the previous worker before its
  process ownership is cleared.
- `/cancel`, app termination, server shutdown, and launch failure all request
  cancellation and converge on the same teardown path.
- The hard readiness timeout is 90 seconds.
- A retry increments the attempt counter and reruns discovery/focus against the
  existing session. It never dispatches the launch command again.

### Process ownership

Capture a Windows process baseline immediately before dispatching launch
commands. Track process identity as `(pid, creationTime)`, preventing PID reuse
from transferring ownership.

A process may become session-owned only through explicit evidence:

1. It is the directly launched process or belongs to its process group.
2. It is a descendant of an owned process.
3. It was created after the launch baseline and its canonical executable path
   is under a validated game root.
4. Playnite reports it as the launched game process and its executable/root is
   validated.

Validated game roots may come from:

- the direct executable's parent directory;
- a specific configured working directory;
- a resolved Steam manifest install directory;
- a Playnite-provided install directory.

Safety rules reject empty paths, drive roots, Windows/system directories,
ProgramData, user-profile roots, and the Steam client root itself. A configured
directory outside `steamapps/common` becomes trusted only after a post-baseline
candidate executable is observed below it. This permits the TEKKEN layout
without introducing broad directory kills.

The orchestrator continually adopts qualifying descendants and same-root
processes while the session is active, covering launchers, anti-cheat helpers,
and games that replace their bootstrap executable.

### Window selection and readiness

Only windows belonging to an owned process are candidates. A candidate must be:

- top-level and visible;
- unowned by another window;
- not cloaked;
- not minimized after restoration;
- non-empty and intersecting the captured display;
- large enough to be an interactive application window.

Candidates are scored using process evidence, client-area size, captured-display
coverage, foreground status, and lifetime. A newly appearing higher-scoring
owned window replaces the current candidate. This allows a small launcher or
external splash to be superseded by the real game window.

The shared Win32 focus utility performs:

- `ShowWindow(..., SW_RESTORE)`;
- thread-input attachment where required;
- temporary topmost promotion;
- `SetForegroundWindow`;
- immediate foreground verification.

Readiness requires the same best window and owned foreground PID to remain
valid across consecutive samples for at least 1.5 seconds, with no superior
candidate appearing during the stabilization window. Separate external splash
windows are therefore withheld. Content rendered inside the final game window,
such as publisher logos, cannot be identified generically and is not treated as
an external splash.

### Teardown

Closing a session operates only on the stored owned identities:

1. Send `WM_CLOSE` to owned top-level game windows.
2. Wait for the configured graceful-exit budget.
3. Terminate remaining owned processes whose creation time still matches.
4. Clean process group, helper state, input state, virtual display, and runtime
   overrides through the existing teardown sequence.

The Steam client and unrelated pre-existing processes are never terminated.
The old install-directory scan remains a compatibility fallback only when it
resolves to a validated root; it is no longer the primary ownership mechanism.

## Launch-State Protocol

The `/launch` response adds optional, backward-compatible fields:

- readiness capability version;
- opaque launch-state token;
- whether readiness is required for this app.

The server exposes a lightweight launch-state read/retry operation under the
same paired-client certificate authentication as `/launch`. The token is bound
to the requesting client and current app session. Another paired client cannot
read or retry it.

Old clients ignore the additional `/launch` fields. A new client launching a
non-Desktop game does not silently reveal video when the host omits the
readiness capability; it shows an actionable incompatible-host error. Desktop
remains compatible with hosts that lack the extension.

## Client Privacy Gate

Replace the overloaded `_isConnecting` decision with independent state:

- `transportConnected`
- `hostGameReady`
- `postReadyFrameRendered`
- `revealCompleted`

For a non-Desktop app, video is eligible for display only when the first three
states are true. Connection success alone does not remove the launch UI.

### Post-readiness frame proof

When the server readiness generation changes to `ready`:

1. Record the current native `framesRendered` counter.
2. Request a fresh IDR through the existing Moonlight `LiRequestIdrFrame()`
   path exposed to the Flutter method channel.
3. Wait until `framesRendered` advances after that baseline.
4. Begin the selected reveal transition.

This prevents a buffered pre-readiness desktop frame from flashing during the
transition.

### Renderer visibility

- Texture rendering remains behind an opaque Flutter launch layer and is not
  inserted as the visible layer until the gate opens.
- Direct Submit receives an explicit native visibility gate on its
  `SurfaceView`; hiding the video must not destroy the surface or reset the
  decoder.
- Stop/reconnect returns both renderer paths to hidden before initiating a new
  connection.
- PiP cannot activate before reveal completes.

### Failure UX

On readiness timeout or terminal failure, the client remains opaque and offers:

- **Retry focus**: retry discovery/focus without relaunching.
- **Close session**: invoke the authoritative teardown and return to library.

No timeout, polling error, missing capability, or animation failure falls
through to raw video.

## Cached Launch Experience

The pre-launch dialog and stream connection overlay become one reusable
`LaunchExperience` composition with the same art key and visual state.

### Art rules

- A validated landscape hero uses `BoxFit.cover`.
- When only a portrait poster exists, render:
  - a static, darkened/softened full-bleed backing layer; and
  - the complete poster in a centered `BoxFit.contain` presentation with safe
    margins and a restrained depth treatment.
- Never use a portrait poster as the sole full-bleed `cover` layer.
- Missing or failed art uses the theme-native gradient and title.

This poster fallback supersedes the full-bleed portrait fallback specified by
`2026-07-24-game-art-contract-design.md` because live TV use demonstrated that
the previous rule destroys meaningful poster content.

### Cache rules

- Both launch phases use `PosterImage.artCacheManager`; no launch artwork uses
  raw `Image.network`.
- Keys remain deterministic by server, app, art role, and source URL.
- The selected launch art is resolved and precached before
  `ImageLoadThrottle.pauseForStream()` reduces the memory budget.
- Disk cache remains valid for 90 days and is used by dimension probes and UI
  rendering.
- Returning to the library must not clear live or disk art caches.
- Tests use a counting HTTP server to prove that a second render/launch uses
  the cached file rather than a new request.

## Global Premium Reveal Effects

Add a persisted global enum to `StreamConfiguration` and a selector under
OPTIONS:

1. **Cinematic Iris** — asymmetric cinematic masks retract around the live
   image with a restrained highlight edge.
2. **Prism Bloom** — the key art resolves through a chromatic light bloom and
   controlled exposure falloff.
3. **Signal Veil** — fine signal bands and a luminous sweep dissolve to the
   current frame; no noisy glitch aesthetic.
4. **Poster Reveal** — contained poster gains depth, expands toward the
   viewport, and cross-resolves into the live game.
5. **Minimal Luxe** — short opacity and scale resolve designed for weak GPUs
   and reduced motion.
6. **Random** — chooses one of the five concrete effects once per launch.

The default is **Random**. Effects animate only opacity, transforms, clips, and
bounded gradient layers. Expensive blur is static/precomposed, not animated.
Reduced-motion policy always substitutes Minimal Luxe with shortened movement;
it never disables the privacy gate.

An animation exception immediately completes to the revealed ready frame. It
can never expose video before the gate.

## Performance Scope

The previously validated two-controller fix remains untouched. Small isolated
drop peaks are not sufficient evidence for another decoder/network change.
This work adds no continuous high-frequency Flutter rebuild loop:

- host readiness polling is bounded and stops at ready/failure;
- immutable snapshots notify only on state/generation changes;
- visual effects exist only during the final short reveal;
- static blur and cached art avoid launch-time decode/download pressure.

## Delivery Checkpoints

The work is integrated as buildable vertical slices. At the end of every work
session:

- no protocol/model field is left implemented on only one side;
- focused regression tests pass;
- `flutter analyze` is run on touched Dart files;
- a debug APK builds successfully;
- the last successful APK is retained until its replacement passes;
- unrelated dirty worktree changes are not reverted or committed.

Planned slices:

1. Server ownership/readiness state machine and tests.
2. Protocol plus client privacy gate on texture and Direct Submit.
3. Authoritative teardown and TEKKEN regression coverage.
4. Cached/fitted launch art.
5. Global reveal selector and five effects.
6. Full build, install, live ADB/log validation, and final documentation.

## Test Plan

### Server

- State transitions are deterministic and terminal states cannot regress to
  active states.
- Desktop never creates a readiness gate.
- Retry does not dispatch a second launch command.
- PID reuse fails the `(pid, creationTime)` ownership check.
- A process created after launch under a validated custom working directory is
  adopted.
- A pre-existing process under that directory is not adopted.
- Drive roots, system roots, and Steam client roots are rejected.
- Window scoring prefers the stable game window over a launcher/splash.
- Readiness requires verified foreground stability.
- Cancellation joins the worker without holding process/config/RTSP locks.
- Graceful close precedes force termination.
- TEKKEN shortcut layout closes owned game processes without terminating Steam.

### Client protocol and gate

- Launch response parses readiness fields without breaking legacy responses.
- Non-Desktop transport success alone does not reveal video.
- Ready alone does not reveal video until `framesRendered` advances.
- Readiness triggers one IDR request per generation.
- Reconnect resets all privacy state before starting native transport.
- Missing capability fails closed for games and remains allowed for Desktop.
- Retry and Close Session call the correct authenticated operations.
- Direct Submit remains hidden without destroying its surface.

### Artwork and settings

- Landscape hero remains full-bleed cover.
- Portrait fallback exposes the entire poster with `BoxFit.contain`.
- Both launch phases use the persistent art cache and stable key.
- Second load performs no second HTTP artwork request.
- All reveal enum values round-trip through JSON and `copyWith`.
- Invalid stored enum values fall back to Random.
- Reduced motion selects Minimal Luxe.
- Random never resolves to Random recursively.

### Device validation

On Fire TV and Chromecast:

- install the same verified APK;
- launch TEKKEN with both controllers connected;
- verify no desktop or stale desktop frame is visible;
- verify TEKKEN becomes and stays foreground;
- close the session and prove its owned process exits while Steam remains;
- repeat with another direct executable game;
- validate each reveal option plus Random;
- revisit library and relaunch to verify art is immediate and cached;
- capture synchronized client/server logs and frame/drop metrics.

## Acceptance Criteria

- A non-Desktop launch never reveals the Windows desktop, including timeout,
  reconnect, missing capability, and Direct Submit paths.
- The selected game window is visible, restored, foreground, and stable before
  reveal.
- Retry never starts a duplicate game instance.
- CLOSE SESSION terminates TEKKEN and other session-owned game processes but
  never kills Steam or unrelated processes.
- Portrait art is understandable in every 16:9 backdrop and is not cropped to
  an arbitrary zoomed region.
- Repeated navigation and launch reuse cached artwork without visible network
  reload.
- OPTIONS persists all five effects and Random globally.
- Fire TV and Chromecast run the same APK successfully with both controllers.
- Final documentation records implementation, tests, APK hash, device serials,
  relevant logs, known limitations, and recovery behavior.

## Non-goals

- Detecting publisher logos or cinematics rendered inside the final game
  window through computer vision.
- Killing all processes under a broad directory or killing the Steam client.
- Reworking the proven controller Binder fix.
- Tuning small drop peaks without a reproducible global cause.
- Making third-party legacy hosts reveal games without the readiness extension.
