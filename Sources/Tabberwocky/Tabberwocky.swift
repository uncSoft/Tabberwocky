//
//  Tabberwocky.swift
//  Style the native macOS DocumentGroup / NSWindow document tab bar.
//
//  MIT License. See LICENSE.
//
//  ⚠️  Tabberwocky reaches into the *private* AppKit tab-bar view tree
//      (NSTabBar / NSTabButton). It is therefore NOT App Store-safe — Apple's
//      review can reject binaries that reference private class names. Gate it
//      behind a non-App-Store build flag, e.g.:
//
//          #if DIRECT_DISTRIBUTION || SETAPP_DISTRIBUTION
//          Tabberwocky.shared.start()
//          #endif
//
//      Single-file drop-in: just add this file to your target. Or use it via
//      Swift Package Manager (`import Tabberwocky`).
//
//  Verified hierarchy (macOS 26.5):
//      NSTabBar
//        └ NSTabBarTrackView → NSTabBarScrollView → NSTabBarClipView → NSTabBarDocumentView
//             └ NSTabButton (one per tab)
//        └ NSTabBarNewTabButton ("+")
//

import AppKit

/// **The entire private-API blast radius, in one place.** Every private class name
/// and KVC key Tabberwocky touches lives here — so when a macOS beta moves something,
/// there's one table to patch, and anyone auditing before they ship can see exactly
/// what's private. Use `Tabberwocky.probe()` to check these against a live window.
public enum TabberwockyPrivateNames {
    // View classes (matched by runtime class name)
    public static let tabBar         = "NSTabBar"
    public static let tabButton      = "NSTabButton"
    public static let newTabButton   = "NSTabBarNewTabButton"
    public static let glassEffect    = "NSGlassEffectView"          // macOS 26 only
    public static let trackView      = "NSTabBarTrackView"
    public static let scrollView     = "NSTabBarScrollView"
    public static let clipView       = "NSTabBarClipView"
    public static let documentView   = "NSTabBarDocumentView"
    public static let backdropLayer  = "CABackdropLayer"            // CALayer subclass
    // KVC keys / selectors
    public static let titleKey       = "title"                      // read
    public static let attributedTitleKey = "attributedTitle"       // write
    public static let tintColorKey   = "tintColor"                  // write (glass)

    /// The container views whose layers are cleared so the bar color shows through.
    static let containers = [trackView, scrollView, clipView, documentView]
}

/// The colors Tabberwocky paints the tab bar with. Provide one via
/// `Tabberwocky.shared.style`; it's evaluated on every re-apply, so it can read
/// your app's live appearance.
public struct TabberwockyStyle {
    /// Bar background. Match your titlebar color so the strip blends into the chrome.
    public var barBackground: NSColor
    /// Fill behind the selected tab.
    public var activeFill: NSColor
    /// Fill behind unselected tabs.
    public var inactiveFill: NSColor
    /// Selected tab label color.
    public var activeText: NSColor
    /// Unselected tab label color.
    public var inactiveText: NSColor
    /// Border on the selected tab (nil = no border).
    public var activeOutline: NSColor?
    /// Tint for the "+" new-tab button glyph (nil = leave system default).
    public var newButtonTint: NSColor?
    /// Tab corner radius.
    public var cornerRadius: CGFloat
    /// On macOS 26 each tab is a "liquid glass" view that covers the fill layer.
    /// When true, Tabberwocky tints that glass toward the fill so the color shows.
    /// (You cannot fully *remove* the glass without losing the label — see README.)
    public var flattenGlass: Bool
    /// Label font. `nil` uses the system font at 12pt (medium when active, regular
    /// otherwise). Set this to match a non-default app UI font.
    public var labelFont: NSFont?

    public init(barBackground: NSColor = .windowBackgroundColor,
                activeFill: NSColor = NSColor.controlAccentColor.withAlphaComponent(0.18),
                inactiveFill: NSColor = NSColor.labelColor.withAlphaComponent(0.04),
                activeText: NSColor = .labelColor,
                inactiveText: NSColor = .secondaryLabelColor,
                activeOutline: NSColor? = .controlAccentColor,
                newButtonTint: NSColor? = .controlAccentColor,
                cornerRadius: CGFloat = 7,
                flattenGlass: Bool = true,
                labelFont: NSFont? = nil) {
        self.barBackground = barBackground
        self.activeFill = activeFill
        self.inactiveFill = inactiveFill
        self.activeText = activeText
        self.inactiveText = inactiveText
        self.activeOutline = activeOutline
        self.newButtonTint = newButtonTint
        self.cornerRadius = cornerRadius
        self.flattenGlass = flattenGlass
        self.labelFont = labelFont
    }
}

/// Attribution for apps that integrate Tabberwocky. Using it only requires keeping
/// the MIT license notice; this is a convenience for showing voluntary credit in an
/// About / acknowledgements screen:
///
/// ```swift
/// Text(TabberwockyInfo.attribution)   // "Tab styling by Tabberwocky (MIT) · …"
/// Link("Tabberwocky", destination: TabberwockyInfo.url)
/// ```
public enum TabberwockyInfo {
    public static let name = "Tabberwocky"
    public static let author = "uncSoft"
    public static let license = "MIT"
    public static let url = URL(string: "https://github.com/uncSoft/Tabberwocky")!
    /// A ready-to-display one-line credit.
    public static let attribution = "Tab styling by Tabberwocky (MIT) · github.com/uncSoft/Tabberwocky"
}

/// Styles the native document tab bar to match your app.
///
/// ```swift
/// Tabberwocky.shared.style = {
///     TabberwockyStyle(barBackground: .black,
///                      activeFill: NSColor.white.withAlphaComponent(0.1),
///                      activeOutline: .systemBlue)
/// }
/// Tabberwocky.shared.start()                       // call once at launch
/// // ...later, when your theme changes:
/// Tabberwocky.shared.refresh()
/// ```
@MainActor
public final class Tabberwocky {
    public static let shared = Tabberwocky()
    /// Public so you can instantiate independent stylers (e.g. for tests); most apps
    /// just use `.shared`.
    public init() {}

    /// Base colors. Evaluated on every re-apply so it can read your live theme.
    public var style: () -> TabberwockyStyle = { TabberwockyStyle() }

    /// Optional per-tab fill override — return a color to override `style` for a
    /// single tab (e.g. color-by-tag, a user pick, or a per-index "rainbow").
    /// Return `nil` to fall back to `style`.
    ///
    /// - Parameters:
    ///   - index: the tab's left→right position.
    ///   - documentURL: the tab's document file URL (nil for untitled docs).
    ///   - active: whether this is the selected tab.
    public var fillForTab: ((_ index: Int, _ documentURL: URL?, _ active: Bool) -> NSColor?)?

    /// Optional per-tab **label color** override — symmetric with `fillForTab`.
    /// Return a color to override `style.activeText` / `style.inactiveText` for a
    /// single tab; return `nil` to fall back to the style.
    ///
    /// Use this to keep labels legible on saturated fills (e.g. return white for any
    /// tab that also has a `fillForTab` color), or to color labels by tag.
    ///
    /// - Parameters:
    ///   - index: the tab's left→right position.
    ///   - documentURL: the tab's document file URL (nil for untitled docs).
    ///   - active: whether this is the selected tab.
    public var textForTab: ((_ index: Int, _ documentURL: URL?, _ active: Bool) -> NSColor?)?

    private var scheduled = false
    private var started = false

    /// Start styling. Re-applies automatically on key/update/resize; pass any extra
    /// notification names (e.g. your own "appearance changed" note) to also re-apply.
    /// Safe to call once — repeated calls are ignored (no duplicate observers).
    ///
    /// Call on the main thread. Tabberwocky is `@MainActor`; all of it must run on
    /// the main thread (it touches `NSApp` / `NSView`).
    public func start(reapplyOn extraNotifications: [Notification.Name] = []) {
        guard !started else { return }
        started = true
        let nc = NotificationCenter.default
        let names = [NSWindow.didBecomeKeyNotification,
                     NSWindow.didUpdateNotification,
                     NSWindow.didResizeNotification] + extraNotifications
        for name in names {
            nc.addObserver(self, selector: #selector(scheduleApply), name: name, object: nil)
        }
        scheduleApply()
    }

    /// Force a re-apply now (e.g. after changing your theme or an override color).
    public func refresh() { scheduleApply() }

    @objc private func scheduleApply() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduled = false
                self?.apply()
            }
        }
    }

    /// Style every window that has a document tab bar (not just the key window), so
    /// separate document windows each keep up to date.
    private func apply() {
        for window in NSApp.windows { styleBar(in: window) }
    }

    private func styleBar(in window: NSWindow) {
        let N = TabberwockyPrivateNames.self
        guard let root = window.contentView?.superview,
              let bar = Tabberwocky.firstSubview(of: root, named: N.tabBar) else { return }
        let s = style()

        // Bar: solid background. Hide the blur backdrop + clear containers so it reads.
        bar.tw_setLayerBackground(s.barBackground)
        for sub in bar.layer?.sublayers ?? []
            where String(describing: type(of: sub)) == N.backdropLayer {
            sub.isHidden = true
        }
        for name in N.containers {
            Tabberwocky.firstSubview(of: bar, named: name)?.tw_setLayerBackground(.clear)
        }

        // Tabs left→right. Resolve each tab's document by WINDOW order, not by title:
        // the tab-group's windows are in display order, matching the tab frames, so
        // tab[i] ↔ group.windows[i]. (Title-matching breaks on duplicate filenames
        // and when "show all extensions" is off.)
        let tabs = Tabberwocky.allSubviews(of: bar, named: N.tabButton)
            .sorted { $0.frame.minX < $1.frame.minX }
        let groupWindows = window.tabGroup?.windows ?? [window]
        let activeIndex = Tabberwocky.activeTabIndex(in: window)

        for (i, tab) in tabs.enumerated() {
            let active = (i == activeIndex)
            let url = i < groupWindows.count ? Tabberwocky.documentURL(for: groupWindows[i]) : nil

            // Respect the caller's color exactly (including alpha). The closure gets
            // `active`, so a caller that wants dimming returns a dimmed color itself.
            let fill = fillForTab?(i, url, active) ?? (active ? s.activeFill : s.inactiveFill)
            let text = textForTab?(i, url, active) ?? (active ? s.activeText : s.inactiveText)
            let outline: NSColor? = active ? s.activeOutline : nil
            let font = s.labelFont ?? .systemFont(ofSize: 12, weight: active ? .medium : .regular)

            if s.flattenGlass,
               let glass = Tabberwocky.firstSubview(of: tab, named: N.glassEffect),
               glass.responds(to: NSSelectorFromString("set" + N.tintColorKey.capitalized + ":")) {
                glass.setValue(fill, forKey: N.tintColorKey)
            }
            tab.wantsLayer = true
            if let layer = tab.layer {
                layer.cornerRadius = s.cornerRadius
                layer.masksToBounds = true
                layer.backgroundColor = fill.cgColor
                if let outline {
                    layer.borderWidth = 1.5
                    layer.borderColor = outline.cgColor
                } else {
                    layer.borderWidth = 0
                    layer.borderColor = nil
                }
            }
            Tabberwocky.setLabel(tab, color: text, font: font)
        }

        if let tint = s.newButtonTint,
           let plus = Tabberwocky.firstSubview(of: bar, named: N.newTabButton) as? NSButton {
            plus.contentTintColor = tint
        }
    }

    // MARK: - Helpers (public so consumers can map tabs → documents too)

    /// The document URL backing a tabbed window (its `NSDocument`'s `fileURL`).
    public static func documentURL(for window: NSWindow) -> URL? {
        (window.windowController?.document as? NSDocument)?.fileURL
    }

    /// The document URL for a specific tab view, resolved by its position in the
    /// window's tab group (robust to duplicate filenames / hidden extensions).
    public static func documentURL(forTab tab: NSView, in window: NSWindow) -> URL? {
        guard let root = window.contentView?.superview,
              let bar = firstSubview(of: root, named: TabberwockyPrivateNames.tabBar) else { return nil }
        let tabs = allSubviews(of: bar, named: TabberwockyPrivateNames.tabButton)
            .sorted { $0.frame.minX < $1.frame.minX }
        guard let i = tabs.firstIndex(of: tab) else { return nil }
        let windows = window.tabGroup?.windows ?? [window]
        return i < windows.count ? documentURL(for: windows[i]) : nil
    }

    /// Frontmost tab as a left→right index, via the public `NSWindowTabGroup`.
    /// (NSTabButton is not an NSButton, so it has no `.state` — use the tab group.)
    public static func activeTabIndex(in window: NSWindow) -> Int {
        guard let group = window.tabGroup, let selected = group.selectedWindow,
              let idx = group.windows.firstIndex(of: selected) else { return 0 }
        return idx
    }

    /// First descendant whose runtime class name equals `className`.
    public static func firstSubview(of view: NSView, named className: String) -> NSView? {
        if String(describing: type(of: view)) == className { return view }
        for sub in view.subviews {
            if let hit = firstSubview(of: sub, named: className) { return hit }
        }
        return nil
    }

    /// All descendants whose runtime class name equals `className`.
    public static func allSubviews(of view: NSView, named className: String) -> [NSView] {
        var out: [NSView] = []
        if String(describing: type(of: view)) == className { out.append(view) }
        for sub in view.subviews { out += allSubviews(of: sub, named: className) }
        return out
    }

    /// Read a tab's private `title` safely. Guarded by `responds(to:)` so it returns
    /// nil instead of raising `NSUnknownKeyException` if the key ever disappears.
    static func safeTitle(of tab: NSView) -> String? {
        guard tab.responds(to: NSSelectorFromString(TabberwockyPrivateNames.titleKey)) else { return nil }
        return tab.value(forKey: TabberwockyPrivateNames.titleKey) as? String
    }

    /// Recolor a tab's label via its private-but-KVC-exposed `attributedTitle`.
    /// Note: this replaces the system-provided title; we assume it is plain text
    /// (no system-inserted glyphs / edited markers, which today live elsewhere).
    static func setLabel(_ tab: NSView, color: NSColor, font: NSFont) {
        let setter = "set" + TabberwockyPrivateNames.attributedTitleKey.prefix(1).uppercased()
                   + TabberwockyPrivateNames.attributedTitleKey.dropFirst() + ":"
        guard tab.responds(to: NSSelectorFromString(setter)),
              let title = safeTitle(of: tab), !title.isEmpty else { return }
        let attributed = NSAttributedString(string: title, attributes: [
            .foregroundColor: color, .font: font
        ])
        (tab as AnyObject).setValue(attributed, forKey: TabberwockyPrivateNames.attributedTitleKey)
    }

    // MARK: - Probe (beta canary)

    /// What `probe()` found in a live window — your early-warning for an OS that
    /// moved something private.
    public struct ProbeResult: CustomStringConvertible {
        /// Private view-class name → was it found in the window's view tree.
        public var classes: [String: Bool] = [:]
        /// KVC key → did a sample tab/glass respond to it.
        public var keys: [String: Bool] = [:]
        /// True only if every name Tabberwocky relies on was found.
        public var allFound: Bool {
            // The glass is macOS-26-only; don't fail the canary on its absence.
            classes.filter { $0.key != TabberwockyPrivateNames.glassEffect }.allSatisfy(\.value)
                && keys.values.allSatisfy { $0 }
        }
        public var description: String {
            let c = classes.sorted { $0.key < $1.key }.map { "\($0.value ? "✓" : "✗") \($0.key)" }
            let k = keys.sorted { $0.key < $1.key }.map { "\($0.value ? "✓" : "✗") \($0.key)" }
            return (["classes:"] + c + ["keys:"] + k).joined(separator: "\n")
        }
    }

    /// Walk a live tabbed window and report which private names/keys are still there.
    /// Run it against each macOS beta (in a throwaway DocumentGroup window with ≥2
    /// tabs) — when Apple renames something, the result goes red and tells you which
    /// knob broke, instead of you eyeballing gray tabs. Adopters can also gate their
    /// own `start()` on `probe().allFound`.
    @discardableResult
    public static func probe(in window: NSWindow? = nil) -> ProbeResult {
        let N = TabberwockyPrivateNames.self
        var result = ProbeResult()
        let app = NSApplication.shared   // NSApp can be nil in headless contexts (tests)
        let target = window ?? app.keyWindow ?? app.windows.first
        let root = target?.contentView?.superview
        let bar = root.flatMap { firstSubview(of: $0, named: N.tabBar) }

        result.classes[N.tabBar] = bar != nil
        for name in N.containers {
            result.classes[name] = bar.flatMap { firstSubview(of: $0, named: name) } != nil
        }
        let aTab = bar.flatMap { firstSubview(of: $0, named: N.tabButton) }
        result.classes[N.tabButton] = aTab != nil
        result.classes[N.newTabButton] = bar.flatMap { firstSubview(of: $0, named: N.newTabButton) } != nil
        result.classes[N.glassEffect] = aTab.flatMap { firstSubview(of: $0, named: N.glassEffect) } != nil
        result.classes[N.backdropLayer] = (bar?.layer?.sublayers ?? [])
            .contains { String(describing: type(of: $0)) == N.backdropLayer }

        result.keys[N.titleKey] = aTab?.responds(to: NSSelectorFromString(N.titleKey)) ?? false
        result.keys[N.attributedTitleKey] = aTab?.responds(
            to: NSSelectorFromString("set" + N.attributedTitleKey.prefix(1).uppercased()
                                     + N.attributedTitleKey.dropFirst() + ":")) ?? false
        let glass = aTab.flatMap { firstSubview(of: $0, named: N.glassEffect) }
        result.keys[N.tintColorKey] = glass?.responds(
            to: NSSelectorFromString("set" + N.tintColorKey.prefix(1).uppercased()
                                     + N.tintColorKey.dropFirst() + ":")) ?? false
        return result
    }
}

private extension NSView {
    func tw_setLayerBackground(_ color: NSColor) {
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
    }
}
