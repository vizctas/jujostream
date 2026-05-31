# Design Spec: PC View & Onboarding iOS Apple-Style Redesign

**Date:** 2026-05-31
**Approach:** A (Incremental Refactor)
**Author:** OpenCode
**Status:** Draft — awaiting review

---

## 1. Goal

1. **Onboarding:** Remove "vibe-coded" glass/frozen UI. Adopt solid, iOS Apple-style surfaces with clean hierarchy, generous whitespace, and premium spring animations.
2. **PC View:** Add a visible **Cloud Sync** button, a non-blocking background **health loop** (server reachability + auth session validity), and a **full-page Login/Logout** flow with bold motion.
3. **Performance:** Background checks must have **0% perceptible performance impact** — aggressive throttling, frame-aware scheduling, and zero UI rebuilds unless state changes.

---

## 2. Onboarding Redesign

### 2.1 Visual Direction
- **No glass, no blur, no BackdropFilter.** All cards are **solid opaque surfaces**.
- **Color system:** Use the app's existing `ThemeProvider` colors (surface, background, accent) rather than hardcoded neon indigos. Respect light/dark mode.
- **Typography:** Increase font weights for headlines (`w700`–`w900`), use `height: 1.2` for readability, reduce subtitle opacity to `0.6`.
- **Spacing:** Increase internal card padding from `24` to `28`–`32`. Increase inter-card gap from `16` to `20`.
- **Shape:** Maintain `BorderRadius.circular(24)` but remove `Border.all` on cards unless focused/hovered.

### 2.2 Animation Upgrades (flutter_animate)
Replace the current single `fadeIn + slideY` with a **staggered entrance** per slide:

| Element | Animation | Duration | Delay | Curve |
|---------|-----------|----------|-------|-------|
| Badge (e.g. "EXPERIENCIA...") | fadeIn + slideY(0.08) | 400ms | 0ms | easeOutCubic |
| Headline | fadeIn + slideY(0.12) | 500ms | 80ms | easeOutCubic |
| Body text | fadeIn + slideY(0.06) | 500ms | 160ms | easeOutCubic |
| Bento cards | fadeIn + scale(0.96→1) + slideY(0.10) | 550ms | stagger 100ms | spring(mass:1, stiffness:120, damping:18) |
| Bottom controls | fadeIn | 300ms | 300ms | easeOut |

- **Page transition:** Keep `PageController` with `easeInOutCubic`, but add a parallax `slideX` on the outgoing page (offset * 0.3).
- **Active state:** On gamepad/keyboard focus, cards scale to `1.02` with a `spring` curve and a `1.5` solid border using `tp.accent` (no glow).

### 2.3 Components to Modify
- **`onboarding_screen.dart`**: Swap `OnboardingGlassCard` for a new `_SolidCard`. Remove `OnboardingGlow`. Add staggered `Animate` wrappers.
- **`onboarding_glass_card.dart`**: Rename/refactor to `_SolidCard` — remove `BackdropFilter`, use `tp.surface` background, `tp.background` border only if needed.
- **`onboarding_glow.dart`**: **Delete**. Replace with a subtle, static gradient mesh (`LinearGradient` with 2–3 stops) behind each slide. No animation, no `ValueNotifier` rebuilds.

### 2.4 Content Changes
- **Slide 1** (Welcome): Keep bento layout. Use icon-only bento items with shorter copy.
- **Slide 2** (Gamepad): Keep bento layout. Add a small "Focus Indicator" demo visual (a D-pad crosshair) instead of a giant icon.
- **Slide 3** (Cloud): Keep bento layout. CTA button copy: "Continue" (not "Comenzar con Jujo Cloud") for neutrality; localized via `AppLocalizations`.

---

## 3. PC View Enhancements

### 3.1 App Bar Changes
Add two icon buttons to the right of the existing **Settings** button:

1. **Cloud Sync** (`Icons.sync` or `Icons.cloud_sync`)
   - Visible only when `auth.isSignedIn == true`.
   - Tapping triggers `AuthProvider.pushToCloud()`.
   - Shows a brief `SnackBar` on success/failure.
   - While `auth.isSyncing == true`, icon rotates via `RotationTransition`.
   - Tooltip: "Sync to cloud".

2. **Account** (`Icons.account_circle` or `Icons.cloud_off`)
   - Visible always.
   - If signed in: shows small green dot badge; tap opens a **bottom picker** with options: "My Profile", "Sync Now", "Log Out".
   - If signed out: shows red dot badge; tap opens the **full-page Login screen**.

### 3.2 Background Health Loop (`ServerHealthMonitor`)
A lightweight, scoped monitor that starts when `PcViewScreen` mounts and disposes on unmount.

**What it checks:**
- **Server reachability:** Re-ping each discovered computer every `30s` (debounced; skip if a ping is already in flight for that UUID).
- **Auth session validity:** Check Supabase/Google token expiry every `60s`. If expired, silently clear auth state and trigger a `SnackBar` ("Session expired — please sign in again").

**Performance contract (0% impact):**
- Use a single `Timer.periodic` at `5s` resolution; internally gate checks by their individual intervals.
- All checks run in `unawaited(Future.microtask(...))` — never block the UI isolate.
- If the user is actively streaming (`provider.activeSessionComputer != null`), **halt all checks** except auth expiry (reduced to every `120s`).
- Results update `ComputerProvider` only if `isReachable` actually changed (diff before `notifyListeners`).
- No `setState` in `PcViewScreen` for loop ticks. Use `Consumer<ComputerProvider>` and `Consumer<AuthProvider>` to rebuild only dependent subtrees.

### 3.3 Full-Page Login / Logout Flow

**Login Screen (`CloudAuthScreen` already exists):**
- Reuse `screens/auth/cloud_auth_screen.dart` but wrap its entrance with a **custom page route**:
  - `SlideTransition` from bottom (`Offset(0, 1)` → `Offset(0, 0)`)
  - Curve: `spring(mass:1, stiffness:100, damping:15)`
  - Duration: ~500ms
- On successful login, the route pops with a reverse spring slide, then `AuthProvider.pullFromCloud()` fires.
- On logout, show a brief confirmation dialog (iOS Alert style), then clear state and refresh PC view grid.

**Logout Picker (Bottom Sheet):**
- A `CupertinoActionSheet`-styled bottom picker:
  - "My Profile" → push `ProfileScreen`
  - "Sync Now" → trigger `pushToCloud()` + dismiss
  - "Log Out" → show confirmation, then sign out
- Spring entrance animation: `slideY(1→0)` + `fadeIn`.

### 3.4 Sync Button State Machine
| State | Visual | Action |
|-------|--------|--------|
| Signed out | `Icons.cloud_off` with red badge | Tap → Full-page Login |
| Signed in, idle | `Icons.cloud_done` with green badge | Tap → Bottom picker |
| Signed in, syncing | `Icons.sync` rotating | Tap → no-op (already syncing) |
| Signed in, error | `Icons.cloud_off` with amber badge | Tap → Bottom picker (shows error) |

---

## 4. Architecture & Data Flow

```
PcViewScreen
├── AppBar
│   ├── More (⋮)
│   ├── Settings (⚙)
│   ├── CloudSyncBtn  ← watches AuthProvider.isSyncing
│   └── AccountBtn    ← watches AuthProvider.isSignedIn
├── ServerHealthMonitor (mixin/widget)
│   └── Timer.periodic(5s)
│       ├── every 30s: provider.pingComputer(uuid)
│       └── every 60s: auth.trySilentSignIn() (expiry check)
├── ComputerGrid
│   └── _ComputerCard (solid iOS cards, no blur)
├── NowPlayingBanner
└── BottomSheet / FullPageAuth
```

**No new providers needed.** All state is already in `ComputerProvider` and `AuthProvider`.

---

## 5. Motion Spec

| Interaction | Animation | Duration | Curve |
|-------------|-----------|----------|-------|
| Card focus (gamepad/mouse) | Scale `1.0 → 1.02` | 180ms | spring(120, 18) |
| Card unfocus | Scale `1.02 → 1.0` | 200ms | easeOutCubic |
| Onboarding page enter | Staggered fade + slideY | 400–550ms | easeOutCubic / spring |
| Onboarding page exit | Fade + slideX(parallax) | 400ms | easeInCubic |
| Login screen enter | Slide from bottom | 500ms | spring(100, 15) |
| Login screen exit | Slide to bottom | 400ms | easeInCubic |
| Bottom picker enter | SlideY + fadeIn | 350ms | spring(130, 17) |
| Bottom picker exit | SlideY + fadeOut | 250ms | easeInCubic |
| Sync icon rotation | Continuous 360° | 800ms/rotation | linear |

---

## 6. Error Handling

1. **Health loop network errors:** Log via `Logger`, do not surface to UI unless `isReachable` transitions `true → false` for a previously known server.
2. **Auth expiry:** If silent refresh fails, auto-sign-out and show a non-intrusive `SnackBar`.
3. **Sync failure:** If `pushToCloud()` fails, set `AuthProvider.cloudError`; `CloudSyncBtn` shows amber badge; tapping opens bottom picker with error message.
4. **Missing network:** All pings skipped if `!ConnectivityResult.hasNetwork` (add lightweight connectivity check if not already present; otherwise rely on ping timeout).

---

## 7. Testing Plan

1. **Visual regression:** Screenshot onboarding slides on iPhone SE, iPhone 15 Pro Max, and a 1080p Android TV.
2. **Focus navigation:** Verify D-pad traversal through AppBar icons (More → Settings → Sync → Account → Grid) and back.
3. **Performance:** Profile with Flutter DevTools — confirm no frames dropped during 5-minute idle on PC view with 4 discovered servers.
4. **Auth flow:** Test full-page login → cloud sync → logout → re-login.
5. **Offline:** Disable Wi-Fi; confirm health loop sleeps gracefully and no exceptions thrown.

---

## 8. Files to Touch

| File | Change |
|------|--------|
| `lib/screens/onboarding/onboarding_screen.dart` | Replace glass widgets with solid cards; add staggered animations; remove glow; update copy logic |
| `lib/screens/onboarding/widgets/onboarding_glass_card.dart` | Refactor to solid card (no blur) |
| `lib/screens/onboarding/widgets/onboarding_glow.dart` | **Delete** |
| `lib/screens/pc_view/pc_view_screen.dart` | Add Sync + Account icons; integrate `ServerHealthMonitor` |
| `lib/screens/auth/cloud_auth_screen.dart` | Add custom spring entrance/exit route wrapper |
| `lib/providers/auth_provider.dart` | Add `cloudError` setter for sync failures (already present, verify usage) |
| `lib/providers/computer_provider.dart` | Ensure `pingComputer` and `notifyListeners` diff before rebuild |

---

## 9. Out of Scope

- New theme provider or color system changes
- Changes to `AppViewScreen`, `GameStreamScreen`, or `SettingsScreen`
- Backend API changes
- New localization strings (reuse existing keys where possible)

---

*Please review this spec. Once approved, I will generate the implementation plan.*
