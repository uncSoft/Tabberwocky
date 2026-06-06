import AppKit
import Tabberwocky

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
            switch TabColorStore.shared.choice(for: url) {
            case .fixed(let color): return color
            case .fromTag:
                if let c = TabTagColor.color(in: TabContentRegistry.shared.text(for: url)) { return c }
            case .none:
                break
            }
            if let groupColor = TabGroupManager.shared.color(forTabURL: url) { return groupColor }
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
                                             TabberwockyColorStore.colorsChanged])
    }

    // Don't auto-open a blank untitled doc; we seed our own samples.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    // Don't restore prior sessions — keep the showcase deterministic.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }

    // PoC: two named groups, each becomes its own native tab group.
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

    /// Group colors (teal for Docs, purple for Source).
    private let groupColors: [String: NSColor] = [
        "Docs":   NSColor(red: 0.20, green: 0.62, blue: 0.70, alpha: 1),
        "Source": NSColor(red: 0.55, green: 0.45, blue: 0.95, alpha: 1),
    ]

    /// (url, window) opened per group, in tab order.
    private var groupDocs: [String: [(URL, NSWindow)]] = [:]
    /// The single tab group anchor — every doc tabs onto this one window.
    private var seedAnchor: NSWindow?

    private func seedGroups() {
        for doc in NSDocumentController.shared.documents { doc.close() }
        groupDocs.removeAll(); seedAnchor = nil
        openNext(0)
    }

    private func openNext(_ i: Int) {
        guard i < plan.count else { finishSeeding(); return }
        let (group, file) = plan[i]
        guard let url = Bundle.main.url(forResource: file, withExtension: nil) else {
            openNext(i + 1); return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: false) { [weak self] doc, _, _ in
            guard let self else { return }
            doc?.makeWindowControllers()
            guard let window = doc?.windowControllers.first?.window else { self.openNext(i + 1); return }
            // One native tab group for everything: same identifier, all tabbed onto
            // a single anchor. Groups are a logical layer on top (color + collapse).
            window.tabbingIdentifier = TabGroupManager.tabbingID
            if let anchor = self.seedAnchor {
                anchor.addTabbedWindow(window, ordered: .above)
            } else {
                self.seedAnchor = window
                window.makeKeyAndOrderFront(nil)
            }
            self.groupDocs[group, default: []].append((url, window))
            self.openNext(i + 1)
        }
    }

    private func finishSeeding() {
        let manager = TabGroupManager.shared
        for name in NSOrderedSet(array: plan.map(\.group)).array as! [String] {
            let color = groupColors[name] ?? .systemGray
            manager.register(.init(name: name, color: color), members: groupDocs[name] ?? [])
        }
        // Everything expanded → all tabs visible, skill doc selected.
        manager.apply(select: groupDocs["Docs"]?.first?.0)
        Tabberwocky.shared.refresh()           // color tabs by group
    }
}
