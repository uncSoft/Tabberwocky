# Running the showcase

The canonical build is SwiftPM (so it consumes Tabberwocky exactly as an end user
would). There are two ways to run it.

## 1. Terminal (default)

```sh
./run.sh        # build + (re)launch, one command
```

or the two steps it wraps:

```sh
./build.sh                       # swift build → wrap into DocumentTabsShowcase.app
open DocumentTabsShowcase.app
```

`build.sh` runs `swift build -c release` (resolving the Tabberwocky package), then
wraps the produced binary into a real `.app` with an `Info.plist` that declares the
document types. That bundle step is required — a bare SwiftPM executable has no
`Info.plist`, so `DocumentGroup` can't register its document types and the tabs
won't appear.

> Tip: open the package in Xcode for editing/autocomplete with `xed .` (or
> double-click `Package.swift`). You can build/edit there, but **running** the bare
> executable from Xcode won't show document tabs — use `./run.sh` for a faithful run.

## 2. In Xcode (for ⌘R, breakpoints, the debugger)

SwiftPM can't produce the document-type `.app` on its own, so for an in-IDE
build-and-run you make a small macOS **App** project that adds Tabberwocky as a
local package. This is a personal/testing convenience — keep it local (it's
git-ignored); the repo's source of truth stays the SwiftPM setup above.

One-time setup (~5 min):

1. **Xcode → File → New → Project → macOS → App.**
   - Product Name: `DocumentTabsShowcase`
   - Interface: **SwiftUI**, Language: **Swift**, Storage: **None**
   - Save it anywhere local (e.g. this folder — the `.xcodeproj` is git-ignored).
2. **Delete the two template files** Xcode generated: `…App.swift` and
   `ContentView.swift` (Move to Trash) — we have our own `@main` in
   `ShowcaseApp.swift`.
3. **Add our sources to the app target** (drag into the Project navigator, ensure
   "Target Membership" = the app):
   `ShowcaseApp.swift`, `AppDelegate.swift`, `Theme.swift`, `TextDocument.swift`,
   `TabColoring.swift`.
4. **Add the docs it opens as tabs** to the target (Copy Bundle Resources):
   everything in `Resources/` (the `.txt` and `.md`), the five example `.swift`
   files, and `../../Sources/Tabberwocky/Tabberwocky.swift`. These are loaded via
   `Bundle.main`, so they must be in the app's Resources.
5. **Add the package:** File → *Add Package Dependencies…* → **Add Local…** →
   choose the repo root (`Tabberwocky/`) → add the **Tabberwocky** library product
   to the app target. (`import Tabberwocky` now resolves.)
6. **Declare document types:** target → **Info** → *Document Types*, add:
   - `public.plain-text` — role **Editor**
   - `public.source-code`, `public.swift-source` — role **Viewer**
   - `net.daringfireball.markdown` — role **Viewer**
   (Or paste the `CFBundleDocumentTypes` block from `build.sh` into Info.plist.)
7. **Minimum Deployment:** target → General → **macOS 15.0**.
8. **⌘R.** The bundled app launches under the debugger.

End users who consume Tabberwocky in their own Xcode app follow only step 5, but
with the **released** version instead of a local path:

```
https://github.com/uncSoft/Tabberwocky  →  Up to Next Major: 1.0.0
```
