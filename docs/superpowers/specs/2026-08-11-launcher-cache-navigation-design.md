# Launcher cache and navigation design

Date: 2026-08-11
Status: approved

## Objective

Make the launcher immediately usable on re-entry, keep artwork stable during
fast D-pad navigation, and move library synchronization and metadata refreshes
off the critical interaction path.

## Confirmed causes

1. `AppViewScreen.initState()` calls a destructive `loadApps()` on every new
   launcher route.
2. Returning from a stream calls the same destructive load. It clears `_apps`,
   resets `_enrichedOnce`, and starts RAWG/Steam enrichment again.
3. Automatic enrichment owns both an in-app loading pill and an ongoing Android
   notification even when cached metadata already satisfies most games.
4. Poster prefetch is unbounded per focus event: a thirteen-item window can be
   submitted repeatedly while the D-pad is held.
5. Some themes omit stable artwork cache keys. Big Screen decodes every poster
   at 960 px although only the selected card needs that resolution.
6. Non-classic themes update their internal selection and then notify the
   parent, which rebuilds the entire theme body for the same focus movement.

## Design

### 1. Library freshness policy

`AppListProvider` will expose one entry operation with stale-while-revalidate
semantics:

- Different server or empty memory: restore the persisted catalog first, show
  it immediately, then fetch the authoritative host list.
- Same server with a valid catalog: retain `_apps`; refresh silently only when
  stale.
- Returning from a stream: refresh silently. Never clear posters or restart
  metadata enrichment.
- Explicit retry after an empty/error state remains a forced foreground load.

Successful host refresh timestamps are tracked per server. The screen no longer
owns an independent freshness clock.

### 2. Metadata freshness policy

Automatic RAWG/Steam enrichment runs only when metadata is stale or incomplete.
Its successful timestamp is persisted per server. Manual metadata/art refresh
continues to bypass the TTL.

Automatic background work is silent: no Android notification and no launcher
loading pill. Explicit user-triggered refresh may expose progress.

### 3. Artwork scheduling

Introduce a small launcher artwork prefetch coordinator:

- Stable cache manager and `NvApp.artCacheKey()` for every game-art request.
- Coalesce focus changes; only the newest requested window is relevant.
- Directional, bounded poster window instead of submitting thirteen requests
  on every key event.
- Limit concurrent prefetch decodes to two.
- Poster decode width matches the rendered component.
- Backdrop prefetch remains debounced and uses the actual selected backdrop,
  never the portrait poster at a second oversized width.
- Re-entry prewarms only the selected item and immediate visible neighbours.

Disk cache remains the durable 90-day source. Flutter's image cache is treated
as a bounded decode cache, not as durable storage.

### 4. Rendering isolation

- Provider notifications occur only when visible library content or an error
  actually changes.
- Silent refresh does not toggle foreground loading state.
- Themes that own navigation keep selection local during rapid movement. The
  parent receives the settled selection after the existing debounce.
- Stable keys are added to PS5, Hero and Backbone poster widgets.
- Big Screen uses tile-sized poster decoding; high-resolution art is reserved
  for its selected presentation.

## Failure behavior

- A failed background refresh preserves the last good catalog and remains
  silent.
- A failed foreground first load shows the existing retry/pairing UI.
- Missing/corrupt artwork keeps the existing fallback without invalidating the
  whole library.
- A metadata provider failure does not mark the catalog load as failed.

## Acceptance criteria

1. Re-entering the same server never empties a valid launcher.
2. Returning from a stream never starts automatic RAWG/Steam work solely due
   to route return.
3. No automatic metadata Android notification or loading pill appears for a
   warm library.
4. A silent refresh preserves enriched fields and reconciles added/removed
   host applications.
5. All launcher game posters use stable cache keys.
6. Rapid navigation submits a bounded prefetch workload and keeps placeholders
   exceptional after warm-up.
7. Unit/widget tests cover warm re-entry, stale refresh, metadata TTL, silent
   failure preservation, stable keys and prefetch coalescing.
8. Flutter analysis, focused tests and Android release build pass.
9. When ADB devices are available, install and exercise the build on Fire TV
   and Chromecast while capturing launcher/image/cache logs.

## Non-goals

- Replacing the existing metadata database.
- Removing RAWG, Steam, video previews or launcher themes.
- Enlarging the global image cache without workload control.
- Changing streaming/decoder behavior.
