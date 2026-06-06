import AppKit
import Tabberwocky

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Enable native window tabbing and prefer it always, so multiple document
        // windows merge into one tabbed window automatically.
        NSWindow.allowsAutomaticWindowTabbing = true
        UserDefaults.standard.set("always", forKey: "AppleWindowTabbingMode")
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ShowcaseTheme.shared.applyAppearance()
        configureTabberwocky()
        TabContextMenuController.shared.start()   // right-click a tab → pick a color

        // Seed a few sample documents so the showcase opens with styled tabs.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.seedSampleTabs() }
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
        // Per-tab overrides: a right-click/tag color wins; otherwise Rainbow paints
        // each tab by index. Returning nil falls back to the theme's `style`.
        Tabberwocky.shared.fillForTab = { index, url, active in
            switch TabColorStore.shared.choice(for: url) {
            case .fixed(let color): return color
            case .fromTag:
                if let c = TabTagColor.color(in: TabContentRegistry.shared.text(for: url)) { return c }
            case .none:
                break
            }
            if ShowcaseTheme.shared.mode == .rainbow {
                return ShowcaseTheme.shared.tabFillNS(index: index, active: active)
            }
            return nil
        }
        Tabberwocky.shared.start(reapplyOn: [.showcaseThemeChanged, .tabColorsChanged])
    }

    // Don't auto-open a blank untitled doc; we seed our own samples.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    // Don't restore prior sessions — keep the showcase deterministic.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }

    /// The doc that should be the first (active) tab on launch.
    private let firstDoc = "Custom Document Group Tabs.md"

    private func seedSampleTabs() {
        let dc = NSDocumentController.shared
        // Start clean so every launch shows exactly the intended tab set.
        for doc in dc.documents { doc.close() }

        // 8 docs so all 8 Rainbow colors show. The skill write-up leads, then the
        // Tabberwocky library itself, then the rest of this example's source.
        let samples = [
            firstDoc,                       // the styling write-up — first/active
            "Tabberwocky.swift",            // the library
            "Welcome.txt",
            "ShowcaseApp.swift",
            "AppDelegate.swift",
            "Theme.swift",
            "TabColoring.swift",
            "TextDocument.swift",
        ]
        for name in samples {
            guard let url = Bundle.main.url(forResource: name, withExtension: nil) else { continue }
            // With AppleWindowTabbingMode = "always", each opened window joins the
            // existing tab group automatically — no addTabbedWindow needed.
            dc.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }

        // Opening brings each new tab to front, so the last one ends up selected.
        // Re-select the skill doc so it's the active tab on launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let window = dc.documents
                .first(where: { $0.fileURL?.lastPathComponent == self.firstDoc })?
                .windowControllers.first?.window {
                window.tabGroup?.selectedWindow = window
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
