# Contributing

Thanks for your interest. Tabberwocky is small on purpose — issues, ideas, and
focused PRs are all welcome.

## Ground rules

- **Keep the public surface small.** New capability should usually be an opt-in
  hook or an optional file, not new required API.
- **Private AppKit stays gated and fail-soft.** Anything touching the private
  `NSTabBar` tree must `responds(to:)`-guard KVC and do nothing (never crash) when a
  view/key is missing. The core file's App-Store warning must stay accurate.
- **Main-thread only.** Public types are `@MainActor`; keep it that way and keep the
  package clean under Swift 6 strict concurrency.

## Before opening a PR

- `swift build` and `swift test` pass.
- The example still builds and runs: `cd Examples/DocumentTabsShowcase && ./run.sh`.
- If you add a feature, update the README (usage) and `CHANGELOG.md`.
- Note which macOS version(s) you verified on (the private hierarchy is version-fragile).

## Good first contributions

See the README Roadmap — e.g. per-tab icons, custom-font polish, a `willStyleTab`
hook, group persistence, or verifying the private hierarchy on macOS 13/14.
