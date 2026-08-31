# JUJO Stream Client — Impeccable technical audit

Date: 2026-08-30
Baseline: `0836d6eb71823f6f8ada5e93cb32930b279b76c0`

## Audit health score

| # | Dimension | Score | Key finding |
|---|---|---:|---|
| 1 | Accessibility | 2/4 | Core launcher cards support D-pad focus, but several tap actions expose no semantic button, keyboard activation, or 44–48 px target. |
| 2 | Performance | 3/4 | Artwork caching and adaptive motion are strong; a full-screen sigma-36 blur and a few policy-bypassing animations remain. |
| 3 | Responsive design | 3/4 | Main layouts adapt across phone and TV, but compact action targets and fixed interaction chrome remain fragile for touch and couch use. |
| 4 | Theming | 2/4 | Eleven palettes and `ThemeProvider` exist, but launcher/detail widgets still mix semantic tokens with many literal neutral/status colors. |
| 5 | Anti-patterns | 2/4 | The artwork-first direction is clear, but blurred duplicate art, stacked focus shadows, tiny faint labels, and isolated glow treatments add noise. |
| **Total** | | **12/20** | **Acceptable — significant release hardening required** |

## Anti-pattern verdict

The client does not look generically AI-generated: the console navigation, five launcher personalities, artwork policy, and gamepad model are distinctive. It does retain several implementation tells that weaken trust: decorative blur over full-screen art, multiple glow/shadow recipes, literal colors outside theme roles, and small faint utility labels.

## Executive summary

- Severity: **0 P0, 4 P1, 6 P2, 2 P3**.
- Baseline validation: **227 tests pass**; `flutter analyze` reports **45 diagnostics**.
- Streaming contracts are out of remediation scope. No decoder, surface, transport, audio, input protocol, or session lifecycle behavior should change.
- Existing artwork cache keys, 90-day disk cache, bounded decode widths, role-safe hero selection, automatic trailer behavior, and five launcher skins must remain intact.

## Detailed findings

### P1 — Launcher actions lack one shared accessibility contract

- **Location:** `lib/screens/app_view/app_view_screen.dart:1028`, `lib/screens/app_view/app_view_discovery.dart:81`, `lib/screens/app_view/app_view_carousel.dart:255`, `lib/themes/big_screen/big_screen_theme.dart:572`, `lib/widgets/notification_mirror_overlay.dart:176`
- **Category:** Accessibility / Responsive
- **Impact:** Tap-only actions can be skipped by keyboard, D-pad, switch access, and screen readers; several targets are smaller than the 44–48 px product floor.
- **Standard:** WCAG 2.1.1 Keyboard, 2.4.7 Focus Visible, 2.5.8 Target Size.
- **Recommendation:** Introduce one reusable semantic action surface with keyboard/gamepad activation, focus state, and minimum target size; migrate high-traffic launcher actions.
- **Command:** `$impeccable adapt`

### P1 — Async UI continuations use stale `BuildContext`

- **Location:** `lib/screens/pc_view/vibeapollo_screen.dart:301-363`, `lib/widgets/session_metrics_dialog.dart:164-168`
- **Category:** Accessibility / Hardening
- **Impact:** Navigation or snackbars can execute after the widget is disposed, producing runtime exceptions during cancellation, fast back navigation, or network delay.
- **Recommendation:** Capture stable dependencies before awaits and guard every UI continuation with `mounted` or `context.mounted`.
- **Command:** `$impeccable harden`

### P1 — Full-screen Gaussian blur violates artwork and frame-budget contracts

- **Location:** `lib/screens/app_view/app_details_screen.dart:422-449`
- **Category:** Performance / Anti-pattern
- **Impact:** Non-TV devices pay for a sigma-36 full-screen blur on every details view; the result also duplicates and obscures official hero art, explicitly rejected by `PRODUCT.md`.
- **Recommendation:** Remove the blur path and retain a bounded tonal scrim that preserves text contrast.
- **Command:** `$impeccable optimize`

### P1 — Readable UI text falls below the product contrast/size floor

- **Location:** launcher and details utility labels, including `app_view_grid.dart:346`, `app_view_discovery.dart:53`, `app_details_screen.dart:405`
- **Category:** Accessibility / Theming
- **Impact:** 9–10 px labels combined with faint white are hard to read at couch distance and can fail WCAG AA.
- **Recommendation:** Raise actionable and descriptive labels to at least the product Label role (11 px and `white54` or brighter); keep smaller values only for decorative badges.
- **Command:** `$impeccable typeset`

### P2 — Some motion bypasses `MotionPolicy`

- **Location:** `lib/screens/pc_view/pc_view_screen.dart:143-147`, `lib/screens/pc_view/pc_view_screen.dart:591-596`, `lib/screens/app_view/app_view_carousel.dart:223-246`, `lib/screens/cinematic_intro/cinematic_intro_screen.dart:633`
- **Category:** Performance / Accessibility
- **Impact:** Rearrangement and selection motion can still run under reduced effects; the cinematic uses a back-easing overshoot outside the design contract.
- **Recommendation:** Gate all controllers through `MotionScope` and use bounded ease-out curves.
- **Command:** `$impeccable animate`

### P2 — Theme roles are inconsistently applied

- **Location:** systemic across launcher/detail widgets; static scan found literal neutral/status colors substantially outnumber semantic token reads.
- **Category:** Theming
- **Impact:** A component can look correct in the default palette but drift in the other ten palettes.
- **Recommendation:** Migrate touched interactive surfaces to `ThemeProvider`; keep literal black/white only for artwork scrims or guaranteed contrast, and centralize status roles.
- **Command:** `$impeccable colorize`

### P2 — Static-analysis debt hides regressions

- **Location:** 45 diagnostics reported by `flutter analyze`.
- **Category:** Hardening
- **Impact:** Dead fields, unused code, deprecated APIs, style warnings, and unsafe async context use make genuine regressions harder to spot.
- **Recommendation:** Reach a zero-diagnostic analyzer baseline without altering feature contracts.
- **Command:** `$impeccable polish`

### P2 — Details actions use multiple one-off focus implementations

- **Location:** `lib/screens/app_view/app_details_screen.dart:687`, `:1553`, `:2197`
- **Category:** Accessibility / Anti-pattern
- **Impact:** Focus appearance, target size, semantics, and motion differ between actions on the same screen.
- **Recommendation:** Consolidate onto the shared action primitive while preserving each visual hierarchy.
- **Command:** `$impeccable polish`

### P2 — Resting cards retain stacked shadows and glow recipes

- **Location:** `lib/screens/app_view/app_details_screen.dart:1598-1618`, `:2237-2265`
- **Category:** Anti-pattern / Performance
- **Impact:** Multiple broad shadows increase paint cost and compete with artwork; elevation stops communicating focus.
- **Recommendation:** Keep a single bounded focus shadow and tonal rest surfaces.
- **Command:** `$impeccable quieter`

### P2 — Monolithic screens increase regression radius

- **Location:** `settings_screen.dart` (6458 lines), `game_stream_screen.dart` (3650), `app_view_screen.dart` family (3320+ parts), `app_details_screen.dart` (2805).
- **Category:** Performance / Maintainability
- **Impact:** Small UI changes require broad rebuild/review surfaces and make feature-boundary testing difficult.
- **Recommendation:** Continue extracting stable, typed components; do not refactor streaming/session code during this UI pass.
- **Command:** `$impeccable extract`

### P3 — Some debug/dead code remains in production paths

- **Location:** analyzer-listed unused members and `debugPrint` traces in launcher video scheduling.
- **Category:** Polish
- **Impact:** Noise increases maintenance cost and makes runtime logs harder to interpret.
- **Recommendation:** Remove dead members and keep only structured, actionable diagnostics.
- **Command:** `$impeccable polish`

### P3 — Utility copy mixes localized and fixed English labels

- **Location:** launcher hints such as `Grid`, `Settings`, `Details`, `Fav`.
- **Category:** Hardening / Accessibility
- **Impact:** Spanish users receive a partially translated console surface.
- **Recommendation:** Route user-facing copy through `AppLocalizations` as keys are added; preserve controller glyphs.
- **Command:** `$impeccable clarify`

## Positive findings to preserve

- Stable role-based cache keys, bounded image decode dimensions, and a long-lived disk cache directly address prior poster reload problems.
- `GameArtPolicy` prioritizes dedicated landscape heroes and refuses to stretch portrait posters into banners.
- `MotionPolicy` already distinguishes reduced, constrained, standard, and premium tiers without disabling automatic trailers.
- Grid and carousel rendering are lazy and use bounded cache extents.
- Five launcher skins implement a stable contract and retain distinct motion personalities.
- Full baseline test suite passes, including artwork, launcher-cache, streaming negotiation, audio, startup, and motion-policy contracts.

## Approved remediation order

1. **P1 `$impeccable harden`** — async lifecycle safety and zero analyzer diagnostics.
2. **P1 `$impeccable optimize`** — remove the full-screen blur and avoid unnecessary animation work.
3. **P1 `$impeccable adapt`** — shared accessible action primitive and 48 px launcher targets.
4. **P2 `$impeccable quieter`** — reduce stacked shadows/glows while keeping each skin's personality.
5. **P2 `$impeccable polish`** — token alignment, tests, builds, and re-audit.

## Post-remediation re-audit

| Dimension | Before | After | Evidence |
|---|---:|---:|---|
| Accessibility | 2/4 | 3/4 | Shared semantic action primitive, keyboard/gamepad activation, visible focus, and 48 px targets on high-traffic launcher actions. |
| Performance | 3/4 | 4/4 | Full-screen blur removed, continuous motion policy-gated, resting shadow work reduced, and automatic trailers preserved. |
| Responsive design | 3/4 | 4/4 | Compact actions now retain TV/touch target floors and controller navigation behavior. |
| Theming | 2/4 | 2/4 | Touched focus surfaces use theme roles; systemic literal-color migration remains intentionally outside this bounded pass. |
| Anti-patterns | 2/4 | 4/4 | Duplicate blurred art, overshoot easing, stacked resting glows, and one-off action behavior removed from the audited surfaces. |
| **Total** | **12/20** | **17/20** | **Good — release hardened; remaining debt is non-blocking theme localization/refactoring.** |

### Delivered controls

- `AccessibleAction` centralizes semantics, D-pad/keyboard activation, focus indication, reduced-motion timing, tooltips, and minimum target size.
- Dedicated landscape artwork remains the first-choice hero. Portrait posters are not promoted into banners.
- Automatic trailers and all five launcher personalities remain functional; constrained motion degrades effects, not features.
- Decoder, transport, audio, DirectSubmit, ABR, session lifecycle, and game input protocol were not modified.
- Async UI continuations now guard widget lifetime; the analyzer baseline is zero diagnostics.

### Verification

- `flutter analyze`: **0 diagnostics** (previously 45).
- Full Flutter suite: **232 passed, 0 failed** (previously 227 tests).
- Play release built and policy-verified: `app-play-release.apk`; installer permission absent.
- Fire TV release built and policy-verified: `app-directfire-release.apk`; installer permission present.
- Both APKs share the approved signer and package `com.vizcorp.moonlight_jujo_stream`.
- Fire TV (`AFTKRT`) installed with data-preserving replacement and exercised through splash, host selection, launcher load, artwork recovery, and rapid D-pad traversal.
- Fire TV runtime result: app remained resumed; no fatal exception, ANR, Flutter error, unhandled exception, or out-of-memory event observed.
- Chromecast received the Play artifact and was not used for the interactive smoke test at the owner's request.

### Rollback

- Source checkpoint: `checkpoint/pre-impeccable-client-20260830` at baseline commit `0836d6eb71823f6f8ada5e93cb32930b279b76c0`.
