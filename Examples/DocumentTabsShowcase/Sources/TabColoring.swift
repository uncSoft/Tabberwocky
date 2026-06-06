import AppKit
import Tabberwocky

extension Notification.Name {
    static let tabColorsChanged = Notification.Name("tabColorsChanged")
}

extension ColorTarget {
    var role: TabberwockyColorStore.Role { self == .fill ? .fill : .label }
}

/// How a given document's tab should be colored.
enum TabColorChoice {
    case fixed(NSColor)   // an explicit color the user picked
    case fromTag          // derive (live) from the document's first #tag
}

/// What a color choice applies to.
enum ColorTarget { case fill, label }

/// Per-document color overrides, keyed by file URL. Survives tab switching/reorder
/// because it's keyed by the document, not the tab view. Tracks fill and label
/// independently, so a tab can have (say) a teal fill with a yellow label.
///
/// Fixed color picks are backed by Tabberwocky's `TabberwockyColorStore`, so they
/// PERSIST across launches. `.fromTag` is a live mode (recomputed from the file's
/// tag each time), so it's kept in memory for the session.
final class TabColorStore {
    static let shared = TabColorStore()
    private let persisted = TabberwockyColorStore()   // fixed picks, persisted to UserDefaults
    private var fromTagKeys: Set<String> = []          // session-only "use the #tag" mode

    func choice(for url: URL?, _ target: ColorTarget = .fill) -> TabColorChoice? {
        if let color = persisted.color(for: url, target.role) { return .fixed(color) }
        if let key = key(url, target), fromTagKeys.contains(key) { return .fromTag }
        return nil
    }

    func set(_ choice: TabColorChoice?, for url: URL?, _ target: ColorTarget = .fill) {
        let key = key(url, target)
        switch choice {
        case .fixed(let color):
            if let key { fromTagKeys.remove(key) }
            persisted.setColor(color, for: url, target.role)        // persists + notifies
        case .fromTag:
            persisted.setColor(nil as NSColor?, for: url, target.role)  // drop any fixed color
            if let key { fromTagKeys.insert(key) }
            NotificationCenter.default.post(name: .tabColorsChanged, object: nil)
        case .none:
            if let key { fromTagKeys.remove(key) }
            persisted.setColor(nil as NSColor?, for: url, target.role)  // notifies
        }
    }

    private func key(_ url: URL?, _ target: ColorTarget) -> String? {
        guard let s = url?.absoluteString else { return nil }
        return "\(s)#\(target.role.rawValue)"
    }
}

/// Live document text keyed by URL, so "color from #tag" reflects unsaved edits.
final class TabContentRegistry {
    static let shared = TabContentRegistry()
    private var text: [String: String] = [:]

    func update(_ t: String, for url: URL?) {
        guard let key = url?.absoluteString else { return }
        text[key] = t
    }
    func text(for url: URL?) -> String? {
        guard let key = url?.absoluteString else { return nil }
        return text[key]
    }
}

/// Derive a color from a document's first `#tag`.
enum TabTagColor {
    static func color(in text: String?) -> NSColor? {
        guard let text,
              let range = text.range(of: "#[A-Za-z0-9_][A-Za-z0-9_/-]*",
                                     options: .regularExpression) else { return nil }
        let tag = String(text[range].dropFirst()).lowercased()
        return named[tag] ?? hashed(tag)
    }

    private static let named: [String: NSColor] = [
        "red": rgb(0.95, 0.30, 0.32), "orange": rgb(0.98, 0.56, 0.20),
        "yellow": rgb(0.95, 0.80, 0.22), "green": rgb(0.36, 0.80, 0.42),
        "teal": rgb(0.20, 0.76, 0.76), "blue": rgb(0.30, 0.56, 0.96),
        "purple": rgb(0.58, 0.46, 0.96), "violet": rgb(0.58, 0.46, 0.96),
        "pink": rgb(0.92, 0.40, 0.70), "cyan": rgb(0.30, 0.82, 0.95)
    ]

    /// Stable FNV-1a hash → hue, so the same tag always maps to the same color.
    private static func hashed(_ s: String) -> NSColor {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return NSColor(hue: CGFloat(h % 360) / 360, saturation: 0.62, brightness: 0.95, alpha: 1)
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor {
        NSColor(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Right-click → choose color
final class TabContextMenuController: NSObject {
    static let shared = TabContextMenuController()
    private var monitor: Any?
    private var pendingURL: URL?
    private var pendingTarget: ColorTarget = .fill

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, let window = event.window,
                  let url = self.tabURL(at: event.locationInWindow, in: window) else { return event }
            self.showMenu(for: url, event: event, in: window)
            return nil // consume — we handled this right-click
        }
    }

    /// Find which tab the cursor is over → its document URL.
    private func tabURL(at point: NSPoint, in window: NSWindow) -> URL? {
        guard let root = window.contentView?.superview,
              let bar = TreeSearch.first(in: root, named: "NSTabBar") else { return nil }
        for tab in TreeSearch.all(in: bar, named: "NSTabButton") {
            if tab.convert(tab.bounds, to: nil).contains(point) {
                let title = (tab as AnyObject).value(forKey: "title") as? String
                return Self.documentURL(forTitle: title)
            }
        }
        return nil
    }

    static func documentURL(forTitle title: String?) -> URL? {
        guard let title else { return nil }
        return NSDocumentController.shared.documents
            .first { $0.fileURL?.lastPathComponent == title }?.fileURL
    }

    private var presets: [(String, NSColor)] {
        [("Red", rgb(0.95, 0.30, 0.32)), ("Orange", rgb(0.98, 0.56, 0.20)),
         ("Yellow", rgb(0.95, 0.80, 0.22)), ("Green", rgb(0.36, 0.80, 0.42)),
         ("Teal", rgb(0.20, 0.76, 0.76)), ("Blue", rgb(0.30, 0.56, 0.96)),
         ("Purple", rgb(0.58, 0.46, 0.96)), ("Pink", rgb(0.92, 0.40, 0.70))]
    }

    private func showMenu(for url: URL, event: NSEvent, in window: NSWindow) {
        let menu = NSMenu()
        let header = menu.addItem(withTitle: url.lastPathComponent, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(.separator())

        // Two submenus: the tab fill, and (separately) the label text color.
        menu.addItem(colorMenuItem(title: "Tab Color", target: .fill, url: url))
        menu.addItem(colorMenuItem(title: "Label Color", target: .label, url: url))

        menu.addItem(.separator())
        menu.addItem(moveToGroupMenuItem(url: url))

        if let view = window.contentView?.superview {
            menu.popUp(positioning: nil, at: view.convert(event.locationInWindow, from: nil), in: view)
        }
    }

    /// Submenu listing the groups + "New Group…" to move this tab's document into.
    private func moveToGroupMenuItem(url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: "Move to Group", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for group in appGroups.groups {
            let gi = NSMenuItem(title: group.name, action: #selector(moveToGroup(_:)), keyEquivalent: "")
            gi.target = self
            gi.image = swatch(group.color)
            gi.representedObject = ["url": url, "group": group.id]
            submenu.addItem(gi)
        }
        submenu.addItem(.separator())
        let new = NSMenuItem(title: "New Group…", action: #selector(moveToNewGroup(_:)), keyEquivalent: "")
        new.target = self
        new.representedObject = url
        submenu.addItem(new)
        item.submenu = submenu
        return item
    }

    @objc private func moveToGroup(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let url = info["url"] as? URL, let id = info["group"] as? UUID else { return }
        appGroups.assign(url, to: id)
    }

    @objc private func moveToNewGroup(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let name = Self.promptName(title: "New Group", default: "Group \(appGroups.groups.count + 1)")
        else { return }
        let id = appGroups.addGroup(name)
        appGroups.assign(url, to: id)
    }

    /// Simple text prompt (used for naming new groups).
    static func promptName(title: String, default defaultName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = defaultName
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? defaultName : value
    }

    /// A submenu of preset swatches + custom / from-#tag / clear, all routed to
    /// the given target (the tab's fill or its label).
    private func colorMenuItem(title: String, target: ColorTarget, url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (name, color) in presets {
            let si = NSMenuItem(title: name, action: #selector(pickPreset(_:)), keyEquivalent: "")
            si.target = self
            si.image = swatch(color)
            si.representedObject = ["url": url, "color": color, "target": target]
            submenu.addItem(si)
        }
        submenu.addItem(.separator())
        addItem(to: submenu, "Custom…", #selector(pickCustom(_:)), url, target)
        addItem(to: submenu, "From #tag", #selector(pickFromTag(_:)), url, target)
        submenu.addItem(.separator())
        addItem(to: submenu, "Clear", #selector(clearColor(_:)), url, target)
        item.submenu = submenu
        return item
    }

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector,
                         _ url: URL, _ target: ColorTarget) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = ["url": url, "target": target]
        menu.addItem(item)
    }

    private func info(_ sender: NSMenuItem) -> (url: URL?, target: ColorTarget) {
        let dict = sender.representedObject as? [String: Any]
        return (dict?["url"] as? URL, (dict?["target"] as? ColorTarget) ?? .fill)
    }

    @objc private func pickPreset(_ sender: NSMenuItem) {
        let (url, target) = info(sender)
        guard let color = (sender.representedObject as? [String: Any])?["color"] as? NSColor else { return }
        TabColorStore.shared.set(.fixed(color), for: url, target)
    }
    @objc private func pickFromTag(_ sender: NSMenuItem) {
        let (url, target) = info(sender)
        TabColorStore.shared.set(.fromTag, for: url, target)
    }
    @objc private func clearColor(_ sender: NSMenuItem) {
        let (url, target) = info(sender)
        TabColorStore.shared.set(nil, for: url, target)
    }
    @objc private func pickCustom(_ sender: NSMenuItem) {
        let (url, target) = info(sender)
        pendingURL = url
        pendingTarget = target
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
    }
    @objc private func colorPanelChanged(_ panel: NSColorPanel) {
        TabColorStore.shared.set(.fixed(panel.color), for: pendingURL, pendingTarget)
    }

    private func swatch(_ color: NSColor) -> NSImage {
        let size = NSSize(width: 13, height: 13)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 3, yRadius: 3).fill()
        image.unlockFocus()
        return image
    }
    private func rgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor {
        NSColor(red: r, green: g, blue: b, alpha: 1)
    }
}

/// Shared NSView tree search (used by both the styler and the menu controller).
enum TreeSearch {
    static func first(in view: NSView, named className: String) -> NSView? {
        if String(describing: type(of: view)) == className { return view }
        for sub in view.subviews {
            if let hit = first(in: sub, named: className) { return hit }
        }
        return nil
    }
    static func all(in view: NSView, named className: String) -> [NSView] {
        var out: [NSView] = []
        if String(describing: type(of: view)) == className { out.append(view) }
        for sub in view.subviews { out += all(in: sub, named: className) }
        return out
    }
}
