# Launcher cache and navigation implementation plan

Design: `docs/superpowers/specs/2026-08-11-launcher-cache-navigation-design.md`

## Milestone 1: warm library lifecycle

- Add provider-level library and metadata freshness policy.
- Add regression tests for same-server re-entry, silent reconciliation and
  cached-content preservation on failure.
- Change launcher entry and post-stream return to the warm/silent APIs.
- Keep automatic enrichment invisible; retain explicit refresh progress.
- Run focused provider tests and analyzer.

## Milestone 2: bounded artwork pipeline

- Add a generic latest-window scheduler with a two-task concurrency budget.
- Add deterministic scheduler tests for coalescing, de-duplication and bounds.
- Route launcher poster/backdrop prefetch through the scheduler.
- Use the selected backdrop contract instead of oversized poster prefetch.
- Run focused scheduler/widget tests and analyzer.

## Milestone 3: theme decode and rebuild audit

- Add stable game-art keys to PS5, Hero and Backbone.
- Reduce Big Screen poster decode widths by rendered role.
- Coalesce Big Screen parent selection synchronization.
- Add structural regression tests for theme artwork contracts.
- Run launcher/theme tests and analyzer.

## Milestone 4: delivery verification

- Run all relevant Flutter tests.
- Build the requested Android APK variant without changing streaming code.
- Install and capture launcher/cache behavior when ADB devices are visible.
- Record exact changes and verification evidence in the delivery document.
