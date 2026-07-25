# Game Art Contract Design

**Date:** 2026-07-24  
**Scope:** Jujo.StreamAdmin, Jujo.StreamServer, Jujo.StreamClient  
**Status:** Approved design — Option B

## Goal

Selected games must show excellent-quality official art without promoting a
single gameplay screenshot to primary background.

- Hero/banner target: 1920×1080.
- Minimum full-bleed hero: 1280×720.
- Poster target: about 720×1080.
- No 4K requirement.
- Screenshots belong only to a gallery.

## Art Contract

| Role | Meaning | Allowed presentation |
|---|---|---|
| Poster | Portrait cover | Cards; contained fallback composition |
| Hero | Landscape promotional banner/artwork | Full-bleed selected-game background |
| Screenshot | Gameplay capture | Gallery only |

No role may silently substitute another.

## Source Rules

### Admin

- `image-path`: standard poster.
- `image-path-hires`: high-resolution poster.
- `header-url`: hero/banner only.
- `extra-images`: screenshots/artwork gallery, deduplicated, maximum 8.
- RAWG `background_image` may be hero only when landscape and sufficiently
  large.
- IGDB `artworkUrl` may be hero.
- IGDB `screenshotUrl` must not fall back into `header-url`.

### Server

- `AssetType=2`: `image-path-hires`, falling back to `image-path`.
- `AssetType=3`: `header-url` only; no poster fallback.
- `AssetType=4`: indexed `extra-images`.
- `HasHeroImage=1` only when `header-url` exists.
- `ExtraImageCount` reports gallery size.

This remains backward compatible:

- Old clients receive a better poster through `AssetType=2`.
- New clients guard image aspect ratio when connected to an old server that
  may expose a portrait cover as `AssetType=3`.

### Client

Use an explicit art set:

- `posterUrl`
- `heroImageUrl`
- `screenshotUrls`

Preserve these fields through parsing, merge, persistence, equality, refresh,
and cache updates.

RAWG enrichment:

- Never promote `screenshots.first` to background.
- Never replace `posterUrl` with a landscape background.
- Provider-designated primary background may populate hero fallback only after
  validation.
- Screenshots populate gallery as a list, never primary art.

## Selection Policy

One shared selector serves every theme:

1. Valid hero/banner.
2. High-resolution poster fallback composition.
3. Theme-native empty-art background.

Themes control overlays, gradients, motion, and placement. Themes do not choose
different image roles.

## Presentation

### Hero available

- `BoxFit.cover`
- High quality: decode width 1920.
- Standard/performance: decode width 1280.
- Keep source aspect ratio.

### Poster only

- Sharp foreground poster using `BoxFit.contain`.
- Darkened, blurred extension from same poster behind it.
- Never crop portrait poster as full-screen sharp art.
- Theme may change composition, not source semantics.

### No usable art

Show theme gradient, game title, and icon. Never upscale invalid art.

## Validation

Before full-bleed presentation:

- Image must be landscape.
- Preferred minimum: 1280×720.
- Portrait `AssetType=3` from an old server is reclassified as poster fallback.
- Failed or undersized hero uses poster composition.

Validation result is cached to avoid repeat decoding.

## Cache

- Keep original network asset on disk.
- Decode only to 1920 or 1280 hero target.
- Introduce a new cache namespace/version so old pixelated or misclassified
  images do not survive release.
- Cache keys include app identity, role, and art revision/source identity.
- Gallery remains bounded to 8 entries.

## Error Handling

- Hero failure -> poster composition.
- Poster failure -> theme-native empty state.
- Individual gallery failure -> omit failed item; retain remaining gallery.
- Metadata/provider failure must not replace known-good host art.

## Test Plan

### Admin

- IGDB artwork becomes hero.
- IGDB screenshot never becomes hero.
- Screenshots remain gallery entries.
- Existing valid poster/hero survives failed enrichment.

### Server

- `AssetType=2` prefers hi-res poster.
- `AssetType=3` returns hero only.
- `HasHeroImage` does not treat hi-res poster as hero.
- `AssetType=4` indexes bounded gallery.

### Client

- Parser/provider preserve hero and complete gallery.
- Merge, persistence, and equality include all art fields.
- RAWG screenshots never become poster or hero.
- Selector priority is hero -> poster composition -> empty state.
- Old-server portrait hero is rejected as full-bleed.
- Every theme consumes the shared selector.

## Acceptance Criteria

- No single screenshot automatically appears as selected-game background.
- No portrait poster is sharply cropped across full screen.
- Valid hero renders at 1080p target or 720p minimum.
- Poster fallback remains sharp and correctly framed.
- Screenshots appear together in gallery.
- All themes resolve identical primary art for the same game.
- Cache migration removes previously misclassified art.
- Cached selection changes remain visually smooth and avoid repeat downloads.

## Non-goals

- 4K artwork.
- Rotating screenshots as launcher background.
- AI-generated replacement artwork.
- Redesigning each theme beyond required fallback composition.
