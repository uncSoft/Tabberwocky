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

    public init(barBackground: NSColor = .windowBackgroundColor,
                activeFill: NSColor = NSColor.controlAccentColor.withAlphaComponent(0.18),
                inactiveFill: NSColor = NSColor.labelColor.withAlphaComponent(0.04),
                activeText: NSColor = .labelColor,
                inactiveText: NSColor = .secondaryLabelColor,
                activeOutline: NSColor? = .controlAccentColor,
                newButtonTint: NSColor? = .controlAccentColor,
                cornerRadius: CGFloat = 7,
                flattenGlass: Bool = true) {
        self.barBackground = barBackground
        self.activeFill = activeFill
        self.inactiveFill = inactiveFill
        self.activeText = activeText
        self.inactiveText = inactiveText
        self.activeOutline = activeOutline
        self.newButtonTint = newButtonTint
        self.cornerRadius = cornerRadius
        self.flattenGlass = flattenGlass
    }
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
public final class Tabberwocky {
    public static let shared = Tabberwocky()
    private init() {}

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

    /// Start styling. Re-applies automatically on key/update/resize; pass any extra
    /// notification names (e.g. your own "appearance changed" note) to also re-apply.
    public func start(reapplyOn extraNotifications: [Notification.Name] = []) {
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
            self?.scheduled = false
            self?.apply()
        }
    }

    private func apply() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first,
              let root = window.contentView?.superview,
              let bar = Tabberwocky.firstSubview(of: root, named: "NSTabBar") else { return }
        let s = style()

        // Bar: solid background. Hide the blur backdrop + clear containers so it reads.
        bar.tw_setLayerBackground(s.barBackground)
        for sub in bar.layer?.sublayers ?? []
            where String(describing: type(of: sub)) == "CABackdropLayer" {
            sub.isHidden = true
        }
        for name in ["NSTabBarTrackView", "NSTabBarScrollView",
                     "NSTabBarClipView", "NSTabBarDocumentView"] {
            Tabberwocky.firstSubview(of: bar, named: name)?.tw_setLayerBackground(.clear)
        }

        // Tabs (left→right). Active = the selected window's position in the tab group.
        let tabs = Tabberwocky.allSubviews(of: bar, named: "NSTabButton")
            .sorted { $0.frame.minX < $1.frame.minX }
        let activeIndex = Tabberwocky.activeTabIndex(in: window)
        for (i, tab) in tabs.enumerated() {
            let active = (i == activeIndex)
            let title = (tab as AnyObject).value(forKey: "title") as? String
            let url = Tabberwocky.documentURL(forTitle: title)
            let override = fillForTab?(i, url, active)

            let fill = override.map { $0.withAlphaComponent(active ? 0.95 : 0.5) }
                     ?? (active ? s.activeFill : s.inactiveFill)
            // Label color: per-tab override, else the theme's active/inactive text.
            let text = textForTab?(i, url, active)
                     ?? (active ? s.activeText : s.inactiveText)
            let outline: NSColor? = active ? s.activeOutline : nil

            if s.flattenGlass,
               let glass = Tabberwocky.firstSubview(of: tab, named: "NSGlassEffectView"),
               glass.responds(to: Selector(("setTintColor:"))) {
                glass.setValue(fill, forKey: "tintColor")
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
            Tabberwocky.setLabel(tab, color: text, weight: active ? .medium : .regular)
        }

        if let tint = s.newButtonTint,
           let plus = Tabberwocky.firstSubview(of: bar, named: "NSTabBarNewTabButton") as? NSButton {
            plus.contentTintColor = tint
        }
    }

    // MARK: - Helpers (public so consumers can map tabs → documents too)

    /// The document URL for a tab whose displayed title is `title`.
    public static func documentURL(forTitle title: String?) -> URL? {
        guard let title else { return nil }
        return NSDocumentController.shared.documents
            .first { $0.fileURL?.lastPathComponent == title }?.fileURL
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

    /// Recolor a tab's label via its private-but-KVC-exposed `attributedTitle`.
    static func setLabel(_ tab: NSView, color: NSColor, weight: NSFont.Weight) {
        guard tab.responds(to: Selector(("setAttributedTitle:"))),
              let title = (tab as AnyObject).value(forKey: "title") as? String,
              !title.isEmpty else { return }
        let attributed = NSAttributedString(string: title, attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: 12, weight: weight)
        ])
        (tab as AnyObject).setValue(attributed, forKey: "attributedTitle")
    }
}

private extension NSView {
    func tw_setLayerBackground(_ color: NSColor) {
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
    }
}
