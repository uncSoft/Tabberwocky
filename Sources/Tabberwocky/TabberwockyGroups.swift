//
//  TabberwockyGroups.swift
//  Optional, drop-in "tab groups" for DocumentGroup apps — Safari-ish groups that
//  stay inside ONE window.
//
//  Include this file only if you want grouping. It's independent of the styling in
//  Tabberwocky.swift (though it pairs with it: color tabs by group via `color(forURL:)`).
//
//  How it works: a native tab group is one NSWindow, so you can't put multiple real
//  groups in one window. Instead, ALL documents share one native tab group, and a
//  "group" is a label + color + expanded flag over a SUBSET of those tabs.
//  Collapsing a group orders its windows out of the single stack; expanding re-tabs
//  them in. So it stays one self-contained window.
//
//  Integration sketch (one window-tabbing app):
//
//      let groups = TabberwockyGroups()
//      // as you open each document window:
//      groups.register(window, url: doc.fileURL!, group: "Notes")
//      // color tabs by group (compose with your own fillForTab, or):
//      Tabberwocky.shared.fillForTab = { _, url, _ in groups.color(forURL: url) }
//      Tabberwocky.shared.start(reapplyOn: [TabberwockyGroups.didChange])
//      // drive it from your UI:
//      groups.toggle(group.id)        // collapse / expand
//      groups.assign(url, to: id)     // move a doc to a group
//      groups.addGroup("Drafts")      // new group
//

import AppKit

@MainActor
public final class TabberwockyGroups: ObservableObject {
    /// Posted after any change (assign / toggle / register). Wire it into
    /// `Tabberwocky.shared.start(reapplyOn:)` so tab colors re-apply.
    public static let didChange = Notification.Name("TabberwockyGroupsChanged")

    public struct Group: Identifiable, Equatable {
        public let id = UUID()
        public var name: String
        public var color: NSColor
        public var expanded: Bool = true
        public internal(set) var docs: [URL] = []     // member document URLs, in order
        public static func == (a: Group, b: Group) -> Bool { a.id == b.id }
    }

    /// The shared tabbing identifier all registered windows get (one native group).
    public let tabbingIdentifier: String
    @Published public private(set) var groups: [Group] = []

    private var windowForURL: [String: NSWindow] = [:]
    private var anchor: NSWindow?
    private let palette: [NSColor] = [
        NSColor(red: 0.20, green: 0.62, blue: 0.70, alpha: 1),  // teal
        NSColor(red: 0.55, green: 0.45, blue: 0.95, alpha: 1),  // purple
        NSColor(red: 0.95, green: 0.55, blue: 0.25, alpha: 1),  // orange
        NSColor(red: 0.36, green: 0.74, blue: 0.42, alpha: 1),  // green
        NSColor(red: 0.93, green: 0.40, blue: 0.62, alpha: 1),  // pink
    ]

    private var willCloseObserver: NSObjectProtocol?

    public init(tabbingIdentifier: String = "TabberwockyGroup") {
        self.tabbingIdentifier = tabbingIdentifier
        // Prune state when a document window closes (otherwise we'd hold a strong ref
        // to it forever and keep operating on a dead window).
        willCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.windowWillClose(note.object as? NSWindow) }
        }
    }

    deinit {
        if let willCloseObserver { NotificationCenter.default.removeObserver(willCloseObserver) }
    }

    private func norm(_ url: URL) -> URL { url.standardizedFileURL }

    // MARK: Registration

    /// Add a document window to a group (creating the group if new). Sets the shared
    /// tabbing identifier and tabs the window into the single group.
    public func register(_ window: NSWindow, url: URL, group name: String, color: NSColor? = nil) {
        let url = norm(url)
        window.tabbingIdentifier = tabbingIdentifier
        if let anchor { anchor.addTabbedWindow(window, ordered: .above) }
        else { anchor = window; window.makeKeyAndOrderFront(nil) }
        windowForURL[url.absoluteString] = window
        let id = ensureGroup(name, color: color)
        if let i = groups.firstIndex(where: { $0.id == id }) { groups[i].docs.append(url) }
        changed()
    }

    /// Remove a closed window from all state and re-seat the anchor if needed.
    private func windowWillClose(_ window: NSWindow?) {
        guard let window else { return }
        let staleKeys = windowForURL.filter { $0.value === window }.map(\.key)
        guard !staleKeys.isEmpty else { return }
        for key in staleKeys {
            windowForURL.removeValue(forKey: key)
            for i in groups.indices { groups[i].docs.removeAll { $0.absoluteString == key } }
        }
        if anchor === window { anchor = windowForURL.values.first }
        changed()
        // Re-normalize the remaining tabs once the close settles.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.apply() }
        }
    }

    // MARK: Queries

    public func color(forURL url: URL?) -> NSColor? {
        guard let url else { return nil }
        let u = norm(url)
        return groups.first { $0.docs.contains(u) }?.color
    }
    public func urls(in name: String) -> [URL] { groups.first { $0.name == name }?.docs ?? [] }
    public func count(_ name: String) -> Int { groups.first { $0.name == name }?.docs.count ?? 0 }

    // MARK: Mutations

    /// Collapse / expand a group. Won't collapse the last expanded group.
    public func toggle(_ id: UUID) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        if groups[i].expanded, groups.filter({ $0.expanded }).count <= 1 { return }
        groups[i].expanded.toggle()
        apply(); changed()
    }

    /// Move a document into a group, keeping focus on that document.
    public func assign(_ url: URL, to groupID: UUID) {
        let url = norm(url)
        guard let target = groups.firstIndex(where: { $0.id == groupID }) else { return }
        for i in groups.indices { groups[i].docs.removeAll { $0 == url } }
        groups[target].docs.append(url)
        if !groups[target].expanded { groups[target].expanded = true }
        apply(select: url); changed()
    }

    /// Create a new (empty) group; returns its id.
    @discardableResult
    public func addGroup(_ name: String, color: NSColor? = nil) -> UUID {
        let id = ensureGroup(name, color: color)
        changed()
        return id
    }

    /// Front a document's tab.
    public func select(_ url: URL) {
        guard let window = windowForURL[norm(url).absoluteString] else { return }
        window.tabGroup?.selectedWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    /// Point Tabberwocky's fill at group colors (simple case). To compose with your
    /// own per-tab logic, read `color(forURL:)` inside your `fillForTab` instead.
    public func attachColors(to tabberwocky: Tabberwocky? = nil) {
        let target = tabberwocky ?? .shared
        target.fillForTab = { [weak self] _, url, _ in self?.color(forURL: url) }
    }

    // MARK: Reconcile

    /// Bring the visible stack in line with each group's expanded flag, preserving
    /// the current selection (or `select` if given).
    public func apply(select preferURL: URL? = nil) {
        let visible = groups.filter { $0.expanded }.flatMap(\.docs).compactMap { windowForURL[$0.absoluteString] }
        let hidden  = groups.filter { !$0.expanded }.flatMap(\.docs).compactMap { windowForURL[$0.absoluteString] }
        guard let anchorWindow = visible.first else { return }

        let prefer = preferURL.flatMap { windowForURL[norm($0).absoluteString] }
        let desired = [prefer, NSApp.keyWindow].compactMap { $0 }.first { visible.contains($0) } ?? anchorWindow

        // Front a survivor first so we never hide the visible window with nothing
        // behind it (that blanks the whole window).
        anchorWindow.makeKeyAndOrderFront(nil)

        // Ensure every visible window is in the group.
        for window in visible where window != anchorWindow {
            if anchorWindow.tabGroup?.windows.contains(window) != true {
                anchorWindow.addTabbedWindow(window, ordered: .above)
            }
        }

        // Normalize to the canonical (group, then doc) order. Without this, tabs
        // drift across collapse/expand and close cycles — newly re-added windows
        // land at the end instead of in their group's position.
        if let group = anchorWindow.tabGroup {
            for (target, window) in visible.enumerated() where target < group.windows.count {
                if group.windows.firstIndex(of: window) != target {
                    group.insertWindow(window, at: target)
                }
            }
        }

        for window in hidden { window.orderOut(nil) }

        desired.tabGroup?.selectedWindow = desired
        desired.makeKeyAndOrderFront(nil)
    }

    // MARK: Internals

    @discardableResult
    private func ensureGroup(_ name: String, color: NSColor?) -> UUID {
        if let g = groups.first(where: { $0.name == name }) { return g.id }
        let resolved = color ?? palette[groups.count % palette.count]
        let group = Group(name: name, color: resolved)
        groups.append(group)
        return group.id
    }

    private func changed() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
