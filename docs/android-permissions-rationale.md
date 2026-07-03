# Android Permissions & Sensitive Capabilities — Rationale

Reference for Google Play's Permissions Declaration / Data Safety forms, for a
Play Protect / Safe Browsing appeal, and for internal clarity. Every sensitive
capability here is **user-initiated, consent-gated, and tied to a real feature** —
none are speculative or covert.

> **What this app is:** a Moonlight-based game/desktop **streaming client**. You
> pair it with **your own** host PC (running the Jujo/Sunshine server) and stream
> games to this device. All sensitive capabilities exist to serve that first-party,
> user-owned streaming relationship — not to monitor a third party.

## Why Play Protect / Chrome currently flag the sideloaded APK

The automated classifier reads the **static manifest** and sees a combination that
matches a stalkerware *capability shape* — record audio + read notifications +
network + a self-signed APK with **zero download reputation**, outside Play. It does
**not** run the app, so runtime consent gating and feature opt-in are invisible to
it. The identical capabilities in Play-distributed apps are not flagged because Play
is a trusted source with reputation. See the remediation options at the bottom.

## Permission-by-permission

| Permission | Source | What it does | Why it's needed | Data handling |
|---|---|---|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE` | app | Open the video/audio/control connection to the host; check connectivity | Core streaming | Traffic goes only to the user's paired host (LAN or the user's own relay) |
| `CHANGE_WIFI_MULTICAST_STATE` | app | Receive mDNS multicast | Auto-discover the user's streaming hosts on the LAN | Local discovery only; no data leaves the LAN |
| `CHANGE_WIFI_STATE` | app | Hold a `WifiLock` in `PairingForegroundService` | Keep the Wi-Fi radio active during same-device pairing so the local handshake doesn't drop | No data |
| `WAKE_LOCK` | app | Keep CPU/display awake | Prevent sleep during active video playback of a stream | No data |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE` | app | Run pairing/streaming as a foreground service | A live connection to a **connected device** (the host PC) must survive backgrounding; shown with an ongoing, user-visible notification (no stealth) | No data |
| `VIBRATE` | app | Controller rumble/haptics | Pass game rumble events to the device during gameplay | No data |
| **`RECORD_AUDIO`** | app | Capture the local microphone **only during an active stream**, Opus-encode, send to the host | In-game **voice/mic passthrough** so the mic works in games and voice chat on the host | **Live passthrough only — never recorded or stored.** Gated by the runtime permission prompt; audio flows only while a stream is active, only to the paired host; stops on disconnect |
| `POST_NOTIFICATIONS` | app | Show the foreground-service notification and (optionally) mirrored notifications | Transparency for the active session + the opt-in mirror feature | — |
| **`BIND_NOTIFICATION_LISTENER_SERVICE`** (`JujoNotificationListenerService`) | app | **Optional** notification mirror: forward this device's notifications to a device the user paired | Lets the user see e.g. phone notifications on the TV while gaming | **Opt-in and off by default.** Android forces the user to enable it manually in *Settings → Notification access* — it cannot be auto-enabled. Notifications are sent only to devices the user explicitly paired |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | app | Prompt the user to exempt the app from battery optimization | Optional — keeps the pairing/mirror connection alive in the background if the user wants it | User-prompted, optional; no data |
| `USE_BIOMETRIC`, `USE_FINGERPRINT` | **dependency** (passkey / Credential Manager, for Supabase sign-in) | Biometric confirmation for passkey login | Account sign-in | Handled by the OS Credential Manager / Supabase auth |
| ~~`RECEIVE_BOOT_COMPLETED`~~ | — | — | **Removed 2026-07-03.** It was declared but unused (no boot receiver; the app schedules no notifications; `flutter_local_notifications` 22 does not declare it). Dropping this persistence signal was pure cleanup. | — |

## Defensibility summary (the "reason for being")

1. **Consent-gated.** `RECORD_AUDIO` requires the runtime prompt; notification access
   requires a manual grant in system Settings that the app cannot bypass. Nothing
   sensitive is accessed without an explicit, revocable user action.
2. **Optional, not core.** Both the mic and the notification mirror are opt-in
   features. Core streaming works without either.
3. **First-party only.** Every capability serves the connection between this device
   and the **user's own** paired host/devices. There is no third-party monitoring,
   no covert install, no hidden data collection.
4. **No stealth.** The app has a launcher icon, is fully user-facing, and shows an
   ongoing notification whenever a session/foreground service is active.
5. **Data minimization.** Mic audio is live passthrough, never stored. Mirrored
   notifications go only to user-paired devices. Discovery traffic stays on the LAN.

## Recommended hardening (to strengthen the story before Google asks)

- ✅ **`RECEIVE_BOOT_COMPLETED` removed** (2026-07-03) — it was dead (no boot receiver,
  no scheduled notifications, not required by any dependency). One fewer persistence
  signal in the profile.
- **Prominent in-app disclosure** immediately before enabling the mic and the
  notification mirror (a short screen stating what is accessed and where it goes),
  per Google's prominent-disclosure requirement for sensitive data.
- **Publish a privacy policy** (required by Play for `RECORD_AUDIO` + notification
  access) covering the points above.
- **Distribution:** the only thing that removes the automated flag without changing
  features is a **trusted source** — publishing via Play (internal/closed testing)
  makes both Chrome download-scan and Play Protect trust the app. Reputation over
  time also helps. Sideloaded self-signed builds will keep triggering the heuristic.

## If Google questions us — short answers

- *"Why does a streaming app record audio?"* → In-game microphone / voice passthrough
  to the host during a live stream; live-only, never stored, runtime-consented.
- *"Why notification access?"* → Optional user-enabled mirror of the user's own
  notifications to their own paired device; off by default; manual system grant.
- *"Is this monitoring software?"* → No. It connects a device to the **same user's**
  streaming host; all sensitive features are opt-in, disclosed, and revocable.
