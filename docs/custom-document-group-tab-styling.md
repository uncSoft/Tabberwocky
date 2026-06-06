---
name: custom-document-group-tab-styling
description: >
  Restyle the native macOS DocumentGroup / NSWindow document tab bar (the row of
  tabs above a tabbed window) — bar background, per-tab fill, outline, and label
  colors — without leaving DocumentGroup. Uses the private NSTabBar view tree, so
  it is NOT App Store-safe; gate it to direct/Setapp builds. Verified on macOS 26.5.
---

# Custom DocumentGroup Tabs on macOS

How to give a SwiftUI `DocumentGroup` app **themed document tabs** — colored bar,
per-tab fill, an accent outline on the active tab, and colored labels — while
keeping the native tabbing machinery (Save/Versions/restoration/`⌘1‑9`/etc.).

> **Read this first.** There is **no public API** to style the document tab bar.
> Everything below reaches into private AppKit views (`NSTabBar`, `NSTabButton`).
> It works and is robust enough to ship, but Apple's App Store review can reject
> binaries that reference private class names. **Gate the whole thing behind a
> non-App-Store build flag** (see [App Store safety](#app-store-safety)).

---

## 1. Why this is necessary

A document app built with SwiftUI:

```swift
DocumentGroup(newDocument: MyDocument()) { file in
    EditorView(document: file.$document)
}
```

…gets multi-document **tabs for free** because macOS turns each document window
into a tab via native `NSWindow` tabbing:

```swift
NSWindow.allowsAutomaticWindowTabbing = true   // usually in AppDelegate
window.tabbingMode = .preferred
currentWindow.addTabbedWindow(newWindow, ordered: .above)
```

Those tabs are drawn by the system's private `NSTabBar`. The only **supported**
customization is per-tab text/accessory via `window.tab.attributedTitle` /
`window.tab.accessoryView` — not the bar background, tab fill, shape, or active
styling. To theme the chrome you must style the private view tree directly.

---

## 2. The approach in three moves

1. **Find** the `NSTabBar` by walking down from the window's theme frame.
2. **Style** the bar, each tab, and the `+` button by setting layer colors,
   borders, and (KVC) `attributedTitle`.
3. **Re-apply** on the notifications AppKit fires when it repaints the bar — there
   is no "set once"; the system redraws and you must reassert.

---

## 3. The private view hierarchy (verified macOS 26.5)

Walk from `window.contentView?.superview` (the theme frame). The tab bar tree:

```
NSTabBar                         ← bar; subclass of NSView
├─ (sublayer) CABackdropLayer    ← the bar-wide translucent blur
├─ NSTabBarTrackView
│   └─ NSTabBarScrollView
│       └─ NSTabBarClipView
│           └─ NSTabBarDocumentView
│               ├─ NSTabButton   ← one per tab  (NOT an NSButton — see §5)
│               └─ NSTabButton
└─ NSTabBarNewTabButton          ← the "+"  (this IS a real NSButton)
```

> **Version caveat.** These are private class names and can change between macOS
> releases (the titlebar tree was reorganized around Big Sur, and macOS 26 added
> the "liquid glass" layer). Match class names defensively and fail soft — never
> crash if a node is missing.

Generic helpers used throughout:

```swift
func firstSubview(of view: NSView, named className: String) -> NSView? {
    if String(describing: type(of: view)) == className { return view }
    for sub in view.subviews {
        if let hit = firstSubview(of: sub, named: className) { return hit }
    }
    return nil
}

func subviews(of view: NSView, named className: String) -> [NSView] {
    var out: [NSView] = []
    if String(describing: type(of: view)) == className { out.append(view) }
    for sub in view.subviews { out += subviews(of: sub, named: className) }
    return out
}
```

---

## 4. The themeable pieces, enumerated

Each piece below is independent — apply only the ones you want.

### 4a. Bar background

Set the `NSTabBar`'s own layer background. **Important:** the bar also carries a
`CABackdropLayer` sublayer (a translucent blur) drawn *above* the layer's
background color, so your color won't show until you hide it. Also clear the
intermediate container layers so nothing paints over the bar color.

```swift
bar.wantsLayer = true
bar.layer?.backgroundColor = theme.bar.cgColor

// Hide the blur so the color reads solid.
for sub in bar.layer?.sublayers ?? []
    where String(describing: type(of: sub)) == "CABackdropLayer" {
    sub.isHidden = true
}

// Let the bar color show through the scroll/clip containers.
for name in ["NSTabBarTrackView", "NSTabBarScrollView",
             "NSTabBarClipView", "NSTabBarDocumentView"] {
    if let v = firstSubview(of: bar, named: name) {
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
```

Tip: use the same color your window/titlebar uses so the bar blends into the
chrome instead of looking like a separate strip.

### 4b. Tab fill

Each tab's fill is its `NSTabButton` backing layer. On macOS 26 the tab also
contains an `NSGlassEffectView` that sits *over* the layer, so to make the fill
actually visible you set **both**: the layer background (pre-26 / fallback) and
the glass view's `tintColor` (the public macOS-26 property that colors the glass).

```swift
let fill = isActive ? theme.activeFill : theme.inactiveFill

// macOS 26: tint the glass that covers the layer.
if let glass = firstSubview(of: tab, named: "NSGlassEffectView"),
   glass.responds(to: Selector("setTintColor:")) {
    glass.setValue(fill, forKey: "tintColor")
}

// Backing layer (also gives us corner radius + the outline anchor).
tab.wantsLayer = true
tab.layer?.cornerRadius = 7
tab.layer?.masksToBounds = true
tab.layer?.backgroundColor = fill.cgColor
```

The fill accepts **any color and alpha** — solid brand colors, faint tints,
whatever. (Confirmed by setting tabs to fully saturated colors.) The only limit
is that the glass keeps a slight translucency; you cannot make it perfectly matte
(see [Limitations](#limitations)).

### 4c. Outline (active-tab border)

Use the backing layer's border to mark the active tab. A 1–1.5pt accent border
reads cleanly without a heavy fill.

```swift
if isActive {
    tab.layer?.borderWidth = 1.5
    tab.layer?.borderColor = theme.accent.cgColor
} else {
    tab.layer?.borderWidth = 0
    tab.layer?.borderColor = nil
}
```

### 4d. Label colors

`NSTabButton` is **not** an `NSButton`, but it *is* KVC-compliant for `title`
(read) and `attributedTitle` (write). Build an attributed string from the current
title and set its color/weight. This is how you color/weight the tab label.

```swift
func styleLabel(of tab: NSView, color: NSColor, weight: NSFont.Weight) {
    guard tab.responds(to: Selector("setAttributedTitle:")),
          let title = (tab as AnyObject).value(forKey: "title") as? String,
          !title.isEmpty else { return }
    let attributed = NSAttributedString(string: title, attributes: [
        .foregroundColor: color,
        .font: NSFont.systemFont(ofSize: 12, weight: weight)
    ])
    (tab as AnyObject).setValue(attributed, forKey: "attributedTitle")
}
```

Typical use: accent color + `.medium` on the active tab, a dimmed color +
`.regular` on the rest. You can also swap the per-tab icon via the KVC `image`
property (defaults to the file-type icon).

### 4e. The "+" button

`NSTabBarNewTabButton` *is* a real `NSButton`, so it takes public properties —
recolor the glyph with `contentTintColor` (and/or swap `image`).

```swift
if let plus = firstSubview(of: bar, named: "NSTabBarNewTabButton") as? NSButton {
    plus.contentTintColor = theme.accent
}
```

---

## 5. Detecting the active tab (do NOT use `state`)

Because `NSTabButton` is `NSTabButton ⟵ NSTabBarViewButton ⟵ NSView` (a container,
**not** an `NSControl`), it has no `.state`/`isSelected`. Casting to `NSButton`
silently fails and every tab looks inactive.

Use the **public** tab-group API instead. The active tab is the position of the
selected window within the group's (left→right ordered) windows:

```swift
func activeTabIndex(in window: NSWindow) -> Int {
    guard let group = window.tabGroup,
          let selected = group.selectedWindow,
          let idx = group.windows.firstIndex(of: selected) else { return 0 }
    return idx
}
```

Then sort the discovered `NSTabButton`s by `frame.minX` and match by index.

---

## 6. Re-applying (no polling)

AppKit repaints the bar on its own, wiping your colors. Re-apply on the
notifications that accompany those repaints, **coalesced** so a burst of
`didUpdate` triggers one styling pass per runloop turn:

```swift
let nc = NotificationCenter.default
for name: NSNotification.Name in [NSWindow.didBecomeKeyNotification,
                                  NSWindow.didUpdateNotification,
                                  NSWindow.didResizeNotification,
                                  .myAppearanceChanged] {   // your theme-change note
    nc.addObserver(self, selector: #selector(scheduleApply), name: name, object: nil)
}
```

```swift
private var applyScheduled = false
@objc private func scheduleApply() {
    guard !applyScheduled else { return }
    applyScheduled = true
    DispatchQueue.main.async { [weak self] in
        self?.applyScheduled = false
        self?.applyStyle()
    }
}
```

Avoid a `Timer`. `didUpdate` fires frequently enough (selection change, resize,
key change) that coalesced re-apply keeps the styling stable without a heartbeat.

---

## 7. Limitations

- **You cannot fully flatten the tab.** On macOS 26 the tab's label and icon are
  hosted *inside* the `NSGlassEffectView`. Hiding/removing that view to kill the
  "liquid glass" sheen also removes the label — it comes back blank. You can only
  **tint** the glass (§4b), not remove it. A perfectly matte tab is not
  achievable on Tahoe without losing content. (The bar-wide `CABackdropLayer`
  *can* be hidden — that one's safe — but the per-tab glass cannot.)
- **`NSTabButton` ≠ `NSButton`** — no `.state`; use the tab group (§5).
- **Private hierarchy** — class names/structure can shift across macOS releases;
  match defensively and fail soft.
- **Single tab shows no bar** — the tab bar only appears with ≥2 tabs (or when the
  user has "Always" tabbing). Nothing to style until then.

---

## 8. App Store safety

This references private AppKit classes by name → **not safe for the App Store
binary.** Gate the entire type *and* its `start()` call site:

```swift
#if DIRECT_DISTRIBUTION || SETAPP_DISTRIBUTION
DocumentTabBarStyler.shared.start()
#endif
```

```swift
#if DIRECT_DISTRIBUTION || SETAPP_DISTRIBUTION
final class DocumentTabBarStyler { /* … */ }
#endif
```

Result: App Store users get stock tabs; direct / Setapp users get the themed
ones. Same codebase, no fork.

---

## 9. Complete reference implementation

Drop-in, appearance-driven. Wire your own palette into `Theme.current` and call
`DocumentTabBarStyler.shared.start()` once at launch (gated as above).

```swift
import AppKit

#if DIRECT_DISTRIBUTION || SETAPP_DISTRIBUTION
final class DocumentTabBarStyler {
    static let shared = DocumentTabBarStyler()
    private var applyScheduled = false

    func start() {
        let nc = NotificationCenter.default
        for name: NSNotification.Name in [NSWindow.didBecomeKeyNotification,
                                          NSWindow.didUpdateNotification,
                                          NSWindow.didResizeNotification,
                                          .myAppearanceChanged] {
            nc.addObserver(self, selector: #selector(scheduleApply), name: name, object: nil)
        }
    }

    @objc private func scheduleApply() {
        guard !applyScheduled else { return }
        applyScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.applyScheduled = false
            self?.applyStyle()
        }
    }

    private func applyStyle() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first,
              let root = window.contentView?.superview,
              let bar = firstSubview(of: root, named: "NSTabBar") else { return }
        let theme = Theme.current

        // — Bar background (hide the blur, clear containers) —
        bar.setLayerBackground(theme.bar)
        for sub in bar.layer?.sublayers ?? []
            where String(describing: type(of: sub)) == "CABackdropLayer" {
            sub.isHidden = true
        }
        for name in ["NSTabBarTrackView", "NSTabBarScrollView",
                     "NSTabBarClipView", "NSTabBarDocumentView"] {
            firstSubview(of: bar, named: name)?.setLayerBackground(.clear)
        }

        // — Tabs —
        let tabs = subviews(of: bar, named: "NSTabButton")
            .sorted { $0.frame.minX < $1.frame.minX }
        let activeIndex = activeTabIndex(in: window)
        for (i, tab) in tabs.enumerated() {
            let active = (i == activeIndex)
            let fill = active ? theme.activeFill : theme.inactiveFill

            // Fill (layer + macOS-26 glass tint)
            if let glass = firstSubview(of: tab, named: "NSGlassEffectView"),
               glass.responds(to: Selector("setTintColor:")) {
                glass.setValue(fill, forKey: "tintColor")
            }
            tab.wantsLayer = true
            if let layer = tab.layer {
                layer.cornerRadius = 7
                layer.masksToBounds = true
                layer.backgroundColor = fill.cgColor
                // Outline
                layer.borderWidth = active ? 1.5 : 0
                layer.borderColor = active ? theme.accent.cgColor : nil
            }
            // Label
            styleLabel(of: tab,
                       color: active ? theme.activeText : theme.inactiveText,
                       weight: active ? .medium : .regular)
        }

        // — "+" button —
        if let plus = firstSubview(of: bar, named: "NSTabBarNewTabButton") as? NSButton {
            plus.contentTintColor = theme.accent
        }
    }

    private func styleLabel(of tab: NSView, color: NSColor, weight: NSFont.Weight) {
        guard tab.responds(to: Selector("setAttributedTitle:")),
              let title = (tab as AnyObject).value(forKey: "title") as? String,
              !title.isEmpty else { return }
        let attributed = NSAttributedString(string: title, attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: 12, weight: weight)
        ])
        (tab as AnyObject).setValue(attributed, forKey: "attributedTitle")
    }

    private func activeTabIndex(in window: NSWindow) -> Int {
        guard let group = window.tabGroup, let selected = group.selectedWindow,
              let idx = group.windows.firstIndex(of: selected) else { return 0 }
        return idx
    }

    private func firstSubview(of view: NSView, named className: String) -> NSView? {
        if String(describing: type(of: view)) == className { return view }
        for sub in view.subviews {
            if let hit = firstSubview(of: sub, named: className) { return hit }
        }
        return nil
    }

    private func subviews(of view: NSView, named className: String) -> [NSView] {
        var out: [NSView] = []
        if String(describing: type(of: view)) == className { out.append(view) }
        for sub in view.subviews { out += subviews(of: sub, named: className) }
        return out
    }
}

private extension NSView {
    func setLayerBackground(_ color: NSColor) {
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
    }
}

/// Replace with your app's appearance-derived colors.
private struct Theme {
    let bar, activeFill, inactiveFill, accent, activeText, inactiveText: NSColor

    static var current: Theme {
        let dark = true                                  // ← read from your appearance manager
        let accent = NSColor(red: 0.25, green: 0.62, blue: 1.0, alpha: 1.0)
        let fg: NSColor = dark ? .white : .black
        return Theme(
            bar:          dark ? .black : .windowBackgroundColor,
            activeFill:   fg.withAlphaComponent(dark ? 0.10 : 0.95),
            inactiveFill: fg.withAlphaComponent(dark ? 0.035 : 0.04),
            accent:       accent,
            activeText:   accent,
            inactiveText: fg.withAlphaComponent(0.55)
        )
    }
}
#endif
```

---

## 10. Adapting to your app

1. **Palette** — replace `Theme.current` with your appearance manager's colors;
   match `bar` to your titlebar color so the strip blends in.
2. **Theme-change note** — swap `.myAppearanceChanged` for the notification your
   app posts when its appearance changes, so the tabs re-theme live.
3. **Gate it** — wrap the type + call site in your non-App-Store flag (§8).
4. **Call once** — `DocumentTabBarStyler.shared.start()` at launch
   (e.g. `applicationDidFinishLaunching`).
5. **Optional, functional fills** — since fill takes any color, drive it from data
   instead of decoration: tint a tab by its document's tag, or give unsaved docs a
   distinct fill so dirty tabs stand out.
```
