import AppKit
import Tabberwocky

/// PoC: "tab groups" as a layer over a SINGLE native tab group.
///
/// All documents live in one native tab group (one window), so it's genuinely
/// self-contained. A "group" is a label + color over a subset of those tabs, plus
/// an expanded/collapsed flag. Collapsing orders a group's windows out of the
/// single stack; expanding re-tabs them in. Membership lives in `@Published groups`
/// so the sidebar reacts to assignment changes.
final class TabGroupManager: ObservableObject {
    static let shared = TabGroupManager()
    /// Every document shares this identifier → one native tab group.
    static let tabbingID = "vault"

    struct Group: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var color: NSColor
        var expanded: Bool = true
        var docs: [URL] = []                 // member document URLs, in order
        static func == (a: Group, b: Group) -> Bool { a.id == b.id }
    }

    @Published private(set) var groups: [Group] = []
    private var windowForURL: [String: NSWindow] = [:]

    private let palette: [NSColor] = [
        NSColor(red: 0.20, green: 0.62, blue: 0.70, alpha: 1),  // teal
        NSColor(red: 0.55, green: 0.45, blue: 0.95, alpha: 1),  // purple
        NSColor(red: 0.95, green: 0.55, blue: 0.25, alpha: 1),  // orange
        NSColor(red: 0.36, green: 0.74, blue: 0.42, alpha: 1),  // green
        NSColor(red: 0.93, green: 0.40, blue: 0.62, alpha: 1),  // pink
    ]

    func register(_ group: Group, members: [(URL, NSWindow)]) {
        var g = group
        g.docs = members.map(\.0)
        for (url, window) in members { windowForURL[url.absoluteString] = window }
        groups.append(g)
    }

    // MARK: Queries

    func color(forTabURL url: URL?) -> NSColor? {
        guard let url else { return nil }
        return groups.first(where: { $0.docs.contains(url) })?.color
    }
    func count(_ name: String) -> Int { group(named: name)?.docs.count ?? 0 }
    func urls(in name: String) -> [URL] { group(named: name)?.docs ?? [] }
    private func group(named name: String) -> Group? { groups.first { $0.name == name } }

    // MARK: Mutations

    func toggle(_ id: UUID) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        if groups[i].expanded, groups.filter({ $0.expanded }).count <= 1 { return }  // keep one open
        groups[i].expanded.toggle()
        apply()
    }

    func select(_ url: URL) {
        guard let window = windowForURL[url.absoluteString] else { return }
        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    /// Move a document into a group, keeping focus on that document.
    func assign(_ url: URL, to groupID: UUID) {
        guard let target = groups.firstIndex(where: { $0.id == groupID }) else { return }
        for i in groups.indices { groups[i].docs.removeAll { $0 == url } }
        groups[target].docs.append(url)
        if !groups[target].expanded { groups[target].expanded = true }  // don't hide what you just moved
        apply(select: url)
        Tabberwocky.shared.refresh()   // recolor the tab to its new group
    }

    /// Create a new (empty) group; returns its id.
    @discardableResult
    func addGroup(name: String) -> UUID {
        let color = palette[groups.count % palette.count]
        let group = Group(name: name, color: color)
        groups.append(group)
        return group.id
    }

    // MARK: Reconcile

    /// Bring the visible stack in line with each group's expanded flag, preserving
    /// the current selection (or `select` if given) instead of jumping to the anchor.
    func apply(select preferURL: URL? = nil) {
        let visible = groups.filter { $0.expanded }.flatMap(\.docs).compactMap { windowForURL[$0.absoluteString] }
        let hidden  = groups.filter { !$0.expanded }.flatMap(\.docs).compactMap { windowForURL[$0.absoluteString] }
        guard let anchor = visible.first else { return }

        // Decide what stays selected: the requested doc, else the current key
        // window if it's still visible, else the anchor.
        let preferWindow = preferURL.flatMap { windowForURL[$0.absoluteString] }
        let currentKey = NSApp.keyWindow
        let desired = [preferWindow, currentKey].compactMap { $0 }.first { visible.contains($0) } ?? anchor

        // Front a survivor first, so we never hide the visible window with nothing
        // behind it (that blanked the whole window before).
        anchor.makeKeyAndOrderFront(nil)
        for window in visible where window != anchor {
            if anchor.tabGroup?.windows.contains(window) != true {
                anchor.addTabbedWindow(window, ordered: .above)
            }
        }
        for window in hidden { window.orderOut(nil) }

        desired.tabGroup?.selectedWindow = desired
        desired.makeKeyAndOrderFront(nil)
    }
}
