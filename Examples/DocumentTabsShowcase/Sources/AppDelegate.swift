import AppKit
import Tabberwocky

/// The library's group engine, shared across the app (AppDelegate seeds it, the
/// sidebar drives it, the right-click menu assigns into it).
@MainActor let appGroups = TabberwockyGroups(tabbingIdentifier: "vault")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Enable native window tabbing. We DON'T force "always" here: we group
        // windows explicitly (by tabbingIdentifier + addTabbedWindow) so each named
        // group is its own deterministic tab group.
        NSWindow.allowsAutomaticWindowTabbing = true
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ShowcaseTheme.shared.applyAppearance()
        configureTabberwocky()
        TabContextMenuController.shared.start()   // right-click a tab → pick a color

        // Seed sample documents split across two named groups.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.seedGroups() }
    }

    /// Drive the Tabberwocky library from our theme + per-tab overrides.
    private func configureTabberwocky() {
        // Base colors from the current theme.
        Tabberwocky.shared.style = {
            let t = ShowcaseTheme.shared
            return TabberwockyStyle(
                barBackground: t.barNS,
                activeFill:   t.tabFillNS(index: 0, active: true),
                inactiveFill: t.tabFillNS(index: 0, active: false),
                activeText:   t.tabTextNS(active: true),
                inactiveText: t.tabTextNS(active: false),
                activeOutline: t.tabOutlineNS(active: true),
                newButtonTint: t.accentNS
            )
        }
        // Per-tab fill precedence: explicit right-click pick → the tab's GROUP color
        // → Rainbow (theme) → theme style.
        Tabberwocky.shared.fillForTab = { index, url, active in
            // The library respects the alpha we return, so WE dim inactive tabs here
            // for visual hierarchy (the closure knows `active`).
            func dim(_ c: NSColor) -> NSColor { active ? c : c.withAlphaComponent(0.5) }
            switch TabColorStore.shared.choice(for: url) {
            case .fixed(let color): return dim(color)
            case .fromTag:
                if let c = TabTagColor.color(in: TabContentRegistry.shared.text(for: url)) { return dim(c) }
            case .none:
                break
            }
            if let groupColor = appGroups.color(forURL: url) { return dim(groupColor) }
            if ShowcaseTheme.shared.mode == .rainbow {
                return ShowcaseTheme.shared.tabFillNS(index: index, active: active)
            }
            return nil
        }
        // Per-tab label color. An explicit Label Color (right-click → Label Color)
        // wins; otherwise any tab with a custom/rainbow fill gets a white label so
        // it stays readable; otherwise nil → the theme's active/inactive text color.
        Tabberwocky.shared.textForTab = { index, url, active in
            switch TabColorStore.shared.choice(for: url, .label) {
            case .fixed(let color): return color
            case .fromTag:
                if let c = TabTagColor.color(in: TabContentRegistry.shared.text(for: url)) { return c }
            case .none:
                break
            }
            guard Tabberwocky.shared.fillForTab?(index, url, active) != nil else { return nil }
            return NSColor.white.withAlphaComponent(active ? 1.0 : 0.85)
        }
        Tabberwocky.shared.start(reapplyOn: [.showcaseThemeChanged, .tabColorsChanged,
                                             TabberwockyColorStore.colorsChanged,
                                             TabberwockyGroups.didChange])
    }

    // Don't auto-open a blank untitled doc; we seed our own samples.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    // Don't restore prior sessions — keep the showcase deterministic.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }

    // Sample docs split across two starter groups (Docs = teal, Source = purple).
    private let plan: [(group: String, file: String)] = [
        ("Docs",  "Custom Document Group Tabs.md"),
        ("Docs",  "Welcome.txt"),
        ("Docs",  "Architecture.txt"),
        ("Source", "Tabberwocky.swift"),
        ("Source", "ShowcaseApp.swift"),
        ("Source", "AppDelegate.swift"),
        ("Source", "Theme.swift"),
        ("Source", "TabColoring.swift"),
    ]
    private let groupColors: [String: NSColor] = [
        "Docs":   NSColor(red: 0.20, green: 0.62, blue: 0.70, alpha: 1),
        "Source": NSColor(red: 0.55, green: 0.45, blue: 0.95, alpha: 1),
    ]
    private var firstURL: URL?

    private func seedGroups() {
        for doc in NSDocumentController.shared.documents { doc.close() }
        firstURL = nil
        openNext(0)
    }

    private func openNext(_ i: Int) {
        guard i < plan.count else {
            appGroups.apply(select: firstURL)   // all expanded, skill doc selected
            Tabberwocky.shared.refresh()
            return
        }
        let (group, file) = plan[i]
        guard let url = Bundle.main.url(forResource: file, withExtension: nil) else {
            openNext(i + 1); return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: false) { [weak self] doc, _, _ in
            guard let self else { return }
            doc?.makeWindowControllers()
            guard let window = doc?.windowControllers.first?.window else { self.openNext(i + 1); return }
            // Hand the window to the library engine — it sets the shared tabbing id,
            // tabs it into the single group, and records its group membership.
            appGroups.register(window, url: url, group: group, color: self.groupColors[group])
            if self.firstURL == nil { self.firstURL = url }
            self.openNext(i + 1)
        }
    }
}
