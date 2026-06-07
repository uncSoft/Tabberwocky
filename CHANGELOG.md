# Changelog

All notable changes to Tabberwocky. Format loosely follows
[Keep a Changelog](https://keepachangelog.com); the project is pre-2.0, so the API
may still change between minor versions — pin to a version.

## [1.1.0] - 2026-06-07

### Added
- `TabberwockyPrivateNames` — the entire private-API surface (class names + KVC
  keys) in one public table, and `Tabberwocky.probe()` — a beta canary that reports
  which private names are still present in a live window.
- `textForTab` — per-tab label color override, symmetric with `fillForTab`.
- `TabberwockyColorStore` — optional drop-in persistence of per-document fill/label
  colors (UserDefaults, standardized URL keys).
- `TabberwockyGroups` — optional Safari-style tab groups: a color-coded set of
  groups you can **collapse to hide their tabs and expand to restore them in order**.
  Hiding parks a collapsed group's windows in an off-screen "shadow" tab group (no
  private API, no stray singlet windows); restore rebuilds the bar in canonical order
  with minimal moves (no flicker, no tabs flashing active). Includes `willClose`
  cleanup so closed windows don't leak, and `debugLogging` for topology dumps.
- `TabberwockyInfo` — attribution constants (`name`/`author`/`license`/`url` + a
  ready credit string).
- `TabberwockyStyle.labelFont` — override the tab label font.
- `documentURL(for:)` and `documentURL(forTab:in:)` — window-order tab→document
  resolution.
- A `Tests/` target covering ColorStore round-trip and Groups logic.

### Changed
- **All public types are now `@MainActor`** — clean under Swift 6 strict concurrency.
- `fillForTab` now **respects the alpha you return** (no more hardcoded 0.95/0.5
  dimming); dim inactive tabs yourself via the `active` flag if you want it.
- Tab→document resolution uses **tab-group window order** instead of matching the
  title string (fixes duplicate filenames and "hidden extensions").
- Styling now applies to **every window with a tab bar**, not just the key window.
- `start()` is idempotent (no duplicate observers on repeated calls).
- `Tabberwocky.init` is `public` (instantiate independent stylers / for tests).

### Fixed
- The private `title` read is guarded (`responds(to:)`) so a future OS that drops
  the key **fails soft instead of crashing** the host app.
- `TabberwockyGroups` tab ordering no longer drifts across collapse/expand and
  close cycles — `apply()` rebuilds the visible bar in canonical model order each
  pass (moving only out-of-place tabs), and re-applies after a window closes.

## [1.0.0]
- Initial release: native `DocumentGroup`/`NSTabBar` styling (bar, per-tab fill,
  active outline, label colors, `+` button), single-file or SwiftPM, with a
  `DocumentGroup` example app.
