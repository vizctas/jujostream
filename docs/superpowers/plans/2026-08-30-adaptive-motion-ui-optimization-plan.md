# Adaptive motion and UI optimization implementation plan

Design: `docs/superpowers/specs/2026-08-30-adaptive-motion-ui-optimization-design.md`

## Milestone 1: typed adaptive contract

- Add capability tiers, motion tokens, launcher personalities, and scope.
- Preserve the current `MotionPolicy` API while routing it through tokens.
- Add deterministic unit tests for precedence and all five personalities.
- Run focused tests and analyzer.

## Milestone 2: shared primitives and launcher adoption

- Add small focus, switch, and ambient-gating primitives.
- Replace duplicated launcher gating with the resolved policy.
- Ensure rapid focus movement replaces rather than queues visual state.
- Protect automatic trailer and preview behavior with regression coverage.
- Run focused widget/theme tests and analyzer.

## Milestone 3: neglected continuous effects

- Gate and lifecycle-manage marquee, Now Playing pulse, news shimmer, tour
  pulse, backdrop motion, card glow, and branded loops.
- Use static equivalents where ornamental loops are disallowed.
- Keep media, notifications, and all user-enabled extras operational.
- Run focused widget tests and analyzer.

## Milestone 4: global high-value polish

- Migrate primary PC/server focus and high-traffic dialogs to shared tokens.
- Remove only touched hardcoded timings and unsafe layout animations.
- Verify semantics, focus visibility, cancellation, and controller disposal.
- Avoid unrelated changes in large screens.

## Milestone 5: delivery

- Run formatting, static analysis, focused tests, and the full practical suite.
- Build Android release variants used by Chromecast and Fire TV.
- Detect ADB devices, install appropriate APKs, launch, and inspect logcat.
- Record changes and verification evidence in the delivery document.
