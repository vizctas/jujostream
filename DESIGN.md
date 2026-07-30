---
name: JUJO Stream
description: Console-style game launcher for a remote PC library, built to be read across a room and driven by a gamepad.
colors:
  void: "#0E0E1C"
  panel: "#16192E"
  panel-raised: "#1C1D38"
  arcade-violet: "#6C3CE1"
  arcade-violet-lit: "#9B71F5"
  signal-cyan: "#00E5FF"
  signal-cyan-deep: "#00B8D4"
  deep-indigo: "#1B3A6B"
  muted-plum: "#2D2864"
  ink: "#FFFFFF"
  ink-subtle: "#FFFFFF8A"
  ink-faint: "#FFFFFF61"
  ink-divider: "#FFFFFF3D"
  ink-overlay: "#FFFFFF1F"
typography:
  display:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "28px"
    fontWeight: 800
    lineHeight: 1.15
    letterSpacing: "-0.01em"
  headline:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: 1.2
  title:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 700
    lineHeight: 1.3
  body:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.45
  label:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 600
    lineHeight: 1.2
rounded:
  xs: "4px"
  sm: "6px"
  md: "10px"
  lg: "14px"
  xl: "20px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
components:
  button-primary:
    backgroundColor: "{colors.arcade-violet}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "10px 16px"
    typography: "{typography.title}"
  button-primary-hover:
    backgroundColor: "{colors.arcade-violet-lit}"
  button-text:
    backgroundColor: "transparent"
    textColor: "{colors.arcade-violet-lit}"
    rounded: "{rounded.md}"
    padding: "8px 12px"
  card-surface:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.ink}"
    rounded: "{rounded.lg}"
    padding: "{spacing.lg}"
  card-surface-focused:
    backgroundColor: "{colors.panel-raised}"
  chip-filter:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.pill}"
    padding: "6px 12px"
  chip-filter-selected:
    backgroundColor: "{colors.arcade-violet}"
    textColor: "{colors.ink}"
  input-field:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.xs}"
    padding: "8px 0"
  status-dot-online:
    backgroundColor: "{colors.signal-cyan}"
    rounded: "{rounded.pill}"
    size: "8px"
---

# Design System: JUJO Stream

## 1. Overview

**Creative North Star: "The Dark Room"**

The interface is the darkened room; the game artwork is the screen. Every surface in the chrome is a near-black or a low-chroma panel whose only job is to stop competing with the cover art it frames. When a poster loads, it should be the brightest, most saturated thing on the display by a wide margin. This is why all eleven shipped palettes are dark, why the accent is rationed, and why elevation is carried by tonal steps instead of shadow: light in this system belongs to the content, not to the container.

Density is deliberately low for a product-register UI. The primary reading distance is a couch, a TV, or a handheld, not a desk, so the type scale runs small on labels but the touch and focus targets run large, and the focused element is unmistakable from three metres away. Navigation assumes a gamepad first: focus is a first-class visual state, not a keyboard-accessibility afterthought, and every list has a defensible traversal order.

The system explicitly rejects the four things PRODUCT.md names: pixelated portrait covers stretched into landscape, a detached poster floating over a blurred duplicate of itself, decorative effects that sit on top of the artwork, and dense administration UI leaking into the play flow. Configuration surfaces exist, but they live behind their own door and never borrow the launcher's cinematic language to look important.

**Key Characteristics:**
- Dark by default across all eleven palettes; there is no light theme in practice.
- Accent is rationed to action, selection, and state. Never decoration.
- Depth comes from three tonal steps, not from shadow.
- Focus is the loudest state in the system, because a gamepad has no cursor.
- Motion is 140-300 ms, state-carrying, and fully removable via one setting.

## 2. Colors

Eleven complete palettes ship as a user preference; `jujo` is the default and the normative one below. Every palette is a dark room with a different bulb in it: the structure (background → surface → surfaceVariant, plus accent / accentLight / highlight / secondary / muted / warm) is identical, only the hues move. New surfaces must consume the nine `AppThemeColors` roles through `ThemeProvider`, never a literal hex, or they will look correct in exactly one of eleven themes.

### Primary
- **Arcade Violet** (`#6C3CE1`): Primary actions, the selected item in a list or grid, and the filled state of switches and filter chips. This is the app's signature and it is spent sparingly.
- **Arcade Violet Lit** (`#9B71F5`): The lighter sibling. Text buttons, links, focused input underlines, and the hover/overlay wash on top of Arcade Violet. Never a fill on its own.

### Secondary
- **Signal Cyan** (`#00E5FF`): Live and connected state. The online dot on a server card, streaming-session indicators, anything that means *this link is up right now*. Its meaning is temporal; using it as a second brand accent destroys that.
- **Signal Cyan Deep** (`#00B8D4`): The `warm` role in the default palette. Secondary telemetry and metric emphasis where full cyan would shout.

### Tertiary
- **Deep Indigo** (`#1B3A6B`) and **Muted Plum** (`#2D2864`): Structural tints for inactive tracks, selected-row washes, and separators that need hue rather than another grey. Both are backgrounds only; neither has enough contrast against Void to ever carry text.

### Neutral
- **Void** (`#0E0E1C`): The app background. The floor of the room.
- **Panel** (`#16192E`): Cards, sheets, dialogs, app bars. One step up from Void.
- **Panel Raised** (`#1C1D38`): Nested or focused surfaces. The top of the tonal ladder; there is no fourth step.
- **Ink** (`#FFFFFF`, full): Primary text, active icons. 19:1 on Void.
- **Ink Subtle** (`white54`): Secondary text and inactive icons. 6.0:1 on Void — this is the floor for anything a user must read.
- **Ink Faint** (`white38`): 3.6:1 on Void. Large text, disabled states, and decoration only.
- **Ink Divider** (`white24`) and **Ink Overlay** (`white12`): Hairlines and pressed/hover washes. Non-text, always.

### Named Rules

**The Artwork Wins Rule.** Chrome never out-saturates the content it frames. If a screen's most vivid element is a button, a gradient, or a glow rather than the game's own artwork, the screen is wrong. Scrims over artwork are for legibility and are the minimum opacity that achieves 4.5:1 on the text above them — never a mood filter.

**The Rationed Accent Rule.** Arcade Violet covers ≤10% of any screen. Primary action, current selection, and state indicators. It is not a border colour, not a heading colour, not a decorative divider.

**The 4.5 Floor Rule.** `white38` (Ink Faint) is forbidden for body copy, placeholders, form labels, and empty-state text: it measures 3.6:1 on Void and fails WCAG AA. `white54` is the floor for readable text. This is the single most likely regression in this codebase — it appears 44 times as `fontSize: 10` companion text, which is exactly the combination that fails.

**The Eleven Themes Rule.** Every colour reaches the widget through `ThemeProvider` (`tp.accent`, `tp.surface`, `tp.background`, …). A literal `Color(0xFF…)` in a screen or widget is a bug in ten of the eleven themes, and the reviewer's job is to catch it before it ships.

## 3. Typography

**Display Font:** Platform default (Roboto on Android, SF on Apple, Segoe on Windows)
**Body Font:** same family
**Label/Mono Font:** none; there is no monospace role

**Character:** One family, five weights, no pairing. This is correct for the register: a launcher's type is signage, not voice. The personality lives in the artwork and in the motion. Weight, not family, carries the hierarchy — w400 for prose, w600 for labels, w700 for titles, w800 for display, and w900 reserved for the brand wordmark.

### Hierarchy
- **Display** (w800, 28px, 1.15): Screen titles and the largest hero counters. The ceiling; nothing in this app needs to be bigger.
- **Headline** (w700, 22px, 1.2): Section headings and dialog titles.
- **Title** (w700, 17px, 1.3): Game names on cards, server names, list-row primaries, button labels.
- **Body** (w400, 13px, 1.45): Descriptions and prose. The most-used size in the app (90 occurrences). Cap prose at 65-75ch.
- **Label** (w600, 11px, 1.2): Metadata, status text, chip labels, badges.

### Named Rules

**The Fixed Scale Rule.** Sizes are fixed px, never `clamp()` or viewport-relative. Users sit at a consistent distance from a consistent panel; fluid type solves a problem this product does not have and makes a sidebar label shrink for no reason.

**The 10px Ceiling Rule.** `fontSize: 10` and below (44 + 28 occurrences today) is for badge glyphs and numeric chips only. Any sentence a user is expected to read starts at 11px, and at 11px it must be `white54` or brighter. Small *and* faint is the failure mode; pick at most one.

## 4. Elevation

Depth is tonal, not cast. Three steps — Void (`#0E0E1C`) → Panel (`#16192E`) → Panel Raised (`#1C1D38`) — carry every layering relationship in the app, and a surface at rest has no shadow. This is what keeps a grid of twenty covers from turning into a field of floating rectangles.

Shadow is reserved for one job: **the focused element**. Because navigation is gamepad-first and there is no cursor to follow, the focused card lifts and gains an accent-tinted glow, and that is the only place in the system where a shadow means something. The 58 `BoxShadow` instances in the codebase predate this rule and are the main source of visual drift.

### Shadow Vocabulary
- **Focus lift** (`0 8px 24px rgba(0,0,0,0.35)` plus `0 0 18px 3px` of the accent at ~35% alpha): The gamepad-focused card, tile, or row. Never applied on hover alone.
- **Overlay separation** (`0 4px 12px rgba(0,0,0,0.30)`): Dialogs, sheets, and the now-playing banner — surfaces that float above the whole app rather than within a layout.

### Named Rules

**The Flat-At-Rest Rule.** If a card has a shadow while nothing is focused, delete the shadow and move it one tonal step instead. A 2014 app is one where every card is lifted; if the screen looks like a pile of business cards, the elevation is doing the layout's job.

**The Focus Is Loud Rule.** The focused element must be identifiable from across a room in under half a second: tonal step *plus* accent border *plus* glow, all three. Focus is not a subtle 1px outline in this product.

## 5. Components

### Buttons
- **Shape:** Softly rounded (10px). 14px on large surfaces, pill (999px) on chips.
- **Primary:** Arcade Violet fill, white label at Title weight, 10px vertical / 16px horizontal padding. Hover and pressed apply an Arcade Violet Lit overlay at 15%.
- **Hover / Focus:** Hover is an 8% ink wash; focus adds the accent border and glow from Elevation. Transitions run 140 ms on the standard ease-out curve.
- **Text button:** No fill, Arcade Violet Lit label, 8% accent overlay on press. Used for secondary and destructive-adjacent actions.
- **Icon button:** Transparent by default, 8% ink wash on hover, 12% on press, focus overlay explicitly transparent because the focus ring already carries the state.

### Chips
- **Style:** Transparent background, no border, ink label at Label size, pill radius.
- **State:** Selected fills with Arcade Violet at 20% alpha and keeps the ink label. Filter chips and action chips share this vocabulary; do not invent a third.

### Cards / Containers
- **Corner Style:** 14px on server and game cards, 10px on rows and inline panels, 20px on bottom sheets (top corners only).
- **Background:** Panel at rest, Panel Raised when focused or nested.
- **Shadow Strategy:** None at rest. See Elevation.
- **Border:** None at rest; a 2px accent border appears on focus.
- **Internal Padding:** 16px standard, 12px on dense rows, 24px on dialogs.

### Inputs / Fields
- **Style:** Underline only. No fill, no box. The underline is Ink Divider at rest.
- **Focus:** Underline shifts to Arcade Violet Lit. Focus and hover fill colours are explicitly transparent so the underline is the sole signal.
- **Error / Disabled:** Error recolours the underline and adds helper text at Label size in the error hue; disabled drops the label to Ink Faint, which is acceptable here precisely because disabled text is not meant to be read.

### Navigation
- **Style:** Per launcher theme. Five shipped skins (`classic`, `backbone`, `ps5`, `hero`, `bigScreen`) implement the same `LauncherTheme` contract — body, optional app bar, optional side menu, optional status bar — so navigation chrome is swappable without touching the screens underneath.
- **States:** Selected item takes the accent; unselected takes Ink Subtle. On TV and handheld skins the selected item also takes the focus lift.
- **Mobile treatment:** The app bar collapses to title plus overflow; the side menu becomes a sheet.

### Server card *(signature)*
The pairing surface, and the app's most state-dense component. It carries: an optional per-server profile image filling the card (grid) or a circle (focus mode), a status dot in Signal Cyan when online, a cloud badge when the record is cloud-registered, the connection status line, and an action label that changes between *Pair* and *Enter*. The profile image is the server's identity — it is not the wallpaper, which is a separate preference. All six states (unknown, offline, online-unpaired, online-paired, pairing, cert-rejected) must be visually distinct; collapsing any two of them is how users end up staring at a card that says "connected" for a server that will refuse them.

## 6. Do's and Don'ts

### Do:
- **Do** pull every colour from `ThemeProvider`, so a screen survives all eleven palettes.
- **Do** keep readable text at `white54` (6.0:1) or brighter on Void, and reserve `white38` for large or disabled text.
- **Do** carry depth with the three tonal steps — Void, Panel, Panel Raised — before reaching for a shadow.
- **Do** make focus the loudest state on screen: tonal step, accent border, and glow together. A gamepad user has no cursor to fall back on.
- **Do** route every animation through `MotionPolicy`, which already collapses durations to zero under `reduceEffects` or the OS's own reduced-motion flag.
- **Do** let a game's own artwork be the most saturated thing on any screen it appears on.
- **Do** give every one of the server card's six states a distinct read.

### Don't:
- **Don't** enlarge a pixelated portrait cover into landscape artwork. Degrade to the poster or to a typographic fallback instead — PRODUCT.md names this first among anti-references.
- **Don't** float a detached poster over a heavily blurred duplicate of itself. It is the launcher cliché this product exists to avoid.
- **Don't** add decorative effects over a selected game's artwork. Scrims exist for contrast, at the minimum opacity that achieves it, and for nothing else.
- **Don't** let dense administration UI or unfamiliar controls into the play flow. Configuration has its own screens.
- **Don't** use Arcade Violet as a border, heading, or divider colour. It marks action, selection, and state; past ~10% of a screen it stops meaning anything.
- **Don't** use Signal Cyan for anything that isn't live or connected. It is a temporal signal, not a second brand colour.
- **Don't** ship a shadow on a resting card. If it needs separation, it needs a tonal step.
- **Don't** write a literal `Color(0xFF…)` in a screen or widget.
- **Don't** pair `fontSize: 10` with `white38`. Small and faint together is unreadable at couch distance, and it is already the most common contrast failure in this codebase.
- **Don't** introduce a second type family, a display font in a UI label, or a `clamp()` size. One family, five weights, fixed px.

<!--
Resolved 2026-07-28: `AppThemeId.light` was labelled "Light" but is a dark slate
(#2C2F3E, isLight: false). Measured before deciding: 905 hardcoded `Colors.white*`
values across 44 files, and only 8 files branch on `isLight` at all — the game,
plugins, collections, onboarding and cinematic_intro screen groups have none.
Turning it into a real light theme would render most of the app white on white,
so the label became "Slate". The enum value stays `light` because it is
persisted by name and renaming it would orphan every saved selection.

A real light theme remains possible but is a project of its own: it means giving
those 44 files an `isLight` path, not a palette swap.
-->
