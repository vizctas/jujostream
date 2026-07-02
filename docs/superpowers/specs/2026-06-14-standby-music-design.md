# Custom Stand-by Music — Design Spec

**Date:** 2026-06-14
**Status:** Approved (shape), pending written-spec review

## Context

The app's Focus Mode plays a looping "stand-by" ambience track while the user
browses servers. Today the track is one of four bundled presets
(Alone/Lost/Room/Stars), selected via Settings → "Stand-by sound", and the
playback volume is hardcoded at `0.25` in `UiSoundService._getAmbiencePlayer()`.

Users want to (1) use their own music as the stand-by track by picking an mp3
from the device, and (2) control the stand-by playback volume (which also
applies to the bundled presets). This spec covers both.

The app is **gamepad-first**. Every new control must be reachable and operable
with a D-pad/gamepad and must not trap focus. This spec reuses the existing
anti-trap slider and picker patterns rather than introducing new focusable
widgets.

## Decisions (locked)

- **Picker UX:** a 5th option "Custom track…" inside the existing Stand-by
  sound picker dialog (not a separate tile).
- **Live preview:** none. Changes apply on next Focus Mode entry.
- **Track count:** one custom track at a time; re-picking replaces it.

## Existing infrastructure reused

- `file_selector: ^1.0.4` — already a dependency (no new package).
- `UiSoundService._writeToAudioCache(name, bytes)` — copies bytes into the
  app-support `audio_cache` dir and returns a stable absolute path. Picked mp3s
  are persisted here so playback never depends on a transient content URI.
- `_SliderTile` / `_sliderTile(...)` helper — gamepad-safe slider. Anti-trap
  mechanism: `ExcludeFocus(excluding: !_editing)` keeps the raw `Slider` out of
  the focus tree except in edit mode; left/right is only consumed while editing;
  A/Enter enters edit, B/Escape/goBack always exits.
- `_showPicker(ctx, title, opts)` + `_FocusablePickerOption` — gamepad-safe
  option list; first enabled option autofocuses.
- Settings tabs use `FocusTraversalGroup(policy: OrderedTraversalPolicy())` over
  a `ListView` — traversal is **widget order, not index-based**. New tiles are
  safe to insert positionally.

## Design

### 1. Data model — `lib/providers/theme_provider.dart`

- `standby_sound` pref gains a new valid value `'custom'` (alongside
  Alone/Lost/Room/Stars).
- New pref `standby_custom_path` (String, default `''`) — absolute path to the
  imported mp3 in `audio_cache`.
- New pref `standby_custom_name` (String, default `''`) — display name shown in
  the choice tile when `'custom'` is selected.
- New pref `standby_volume` (double, range 0.0–1.0, default `0.25` — matches
  today's hardcoded value).
- Add getters `standbyCustomPath`, `standbyCustomName`, `standbyVolume` and
  setters `setStandbyCustomPath(path, name)`, `setStandbyVolume(v)`.
  `setStandbySound` already exists.

### 2. Import flow — `lib/screens/settings/settings_screen.dart`

- In `_pickStandbySound`, append a 5th option `("Custom track…" / "Pista
  personalizada…", callback)` to the `_showPicker` list.
- The callback:
  1. Dismisses the picker dialog first (so file_selector opens cleanly).
  2. Calls `file_selector.openFile(acceptedTypeGroups: [XTypeGroup(label:
     'audio', extensions: ['mp3','m4a','aac','wav','ogg'])])`.
  3. On a chosen file: read bytes → `UiSoundService.importStandbyTrack(bytes,
     fileName)` → returns a stable path in `audio_cache` →
     `tp.setStandbyCustomPath(path, fileName)` + `tp.setStandbySound('custom')`.
  4. On cancel: no change.
- The Stand-by sound `_choiceTile` value shows `standbyCustomName` when the
  selection is `'custom'`, otherwise the preset name.

### 3. Playback — `lib/services/audio/ui_sound_service.dart`

- New public `importStandbyTrack(Uint8List bytes, String fileName) -> Future<String>`:
  writes to `audio_cache` (reusing `_writeToAudioCache`) under a fixed name
  (e.g. `standby_custom<ext>`) so only one custom track is retained, and
  returns the path.
- In `_playAmbienceAsync()`:
  - If `standby_sound == 'custom'`: read `standby_custom_path`; if the file
    exists and is readable, play it directly (already in cache — skip the asset
    copy step). If missing/unreadable → silent fallback to the `'Alone'` asset.
  - Else: existing preset→asset mapping.
  - Read `standby_volume` (default 0.25) and call `player.setVolume(v)` before
    `play(...)`, replacing the fixed `0.25`.

### 4. Volume UI — `lib/screens/settings/settings_screen.dart`

- Insert a `_sliderTile` **"Stand-by volume" / "Volumen de espera"**
  immediately after the Stand-by sound `_choiceTile` and before the `Language`
  section (tab scope 0), inside the same `FocusTraversalGroup`.
- Range 0–100 (integer divisions), `labelBuilder` shows `${v.round()}%`,
  `value: (tp.standbyVolume * 100)`, `onChanged: (v) =>
  tp.setStandbyVolume(v / 100)`.
- Because it reuses `_sliderTile`, it inherits the anti-trap behavior — no
  custom Slider, no new focus node wiring.

## Gamepad / focus safety (explicit)

- Volume control reuses `_SliderTile` verbatim → `ExcludeFocus` + edit-mode
  gating prevent the D-pad-left/right trap; B always escapes edit mode.
- "Custom track…" reuses `_FocusablePickerOption` → no new focus behavior.
- New tiles are inserted by **widget order** within an
  `OrderedTraversalPolicy` group → no index tables to desync.
- No `SelectableText`, no full-screen `Focus(onKeyEvent:)` wrappers, no raw
  `Slider` outside `ExcludeFocus` (per the project's focus-trap checklist).

## Edge cases

- Custom file deleted/moved externally → falls back to `'Alone'` at play time;
  selection stays `'custom'` (re-pick to fix). No crash.
- Unsupported/corrupt file → `audioplayers` play fails silently (existing
  try/catch in `_playAmbienceAsync`); ambience simply doesn't start.
- Re-picking a track overwrites the single cached file (one-track scope).
- Volume `0.0` → effectively mutes stand-by music; presets included.

## Out of scope (YAGNI)

- Multiple-track library / playlist.
- Live preview of track or volume inside Settings.
- Per-server or per-theme stand-by tracks.
- Trimming/fade controls.

## Verification

1. **Build + install** release APK on the MiBox (gamepad-first target) and a
   phone per the build/test loop.
2. **Gamepad nav, no trap:** with a controller, D-pad down through Settings
   onto "Stand-by volume"; confirm down/up still moves off it without entering
   edit; press A to edit, left/right changes %, B exits — focus never stuck.
3. **Preset volume:** lower volume, enter Focus Mode, confirm ambience is
   quieter; set 0%, confirm silence; restore.
4. **Custom import:** Settings → Stand-by sound → "Custom track…" → pick an mp3;
   confirm tile shows the file name. Enter Focus Mode → custom track plays and
   loops at the set volume.
5. **Persistence:** kill/relaunch app → selection, custom track, and volume
   persist.
6. **Fallback:** delete the cached file (or pick then remove source) → Focus
   Mode falls back to Alone without crashing.
