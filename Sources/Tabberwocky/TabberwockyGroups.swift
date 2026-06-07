//
//  TabberwockyGroups.swift
//  Optional, drop-in document "tab groups" for a DocumentGroup app.
//
//  Include this file only if you want grouping. It pairs with the styling in
//  Tabberwocky.swift (color tabs by group via `color(forURL:)`).
//
//  Design — deliberately stable. All documents live in ONE native tab group (one
//  window), always visible. A "group" is a label + color over a subset of those
//  tabs, plus a sidebar-collapse flag. Group membership drives the tab COLOR.
//
//  We intentionally do NOT hide a group's tabs from the bar. macOS has no supported
//  "hide one tab of a group": doing it by ordering windows out and re-merging them
//  with addTabbedWindow is unstable (tabs pop into their own windows, flicker, or
//  go unresponsive). So grouping here is color + a collapsible sidebar list, not
//  show/hide of the tabs themselves. (See git history for the abandoned shuttle.)
//
//  Integration sketch:
//
//      let groups = TabberwockyGroups()
//      groups.register(window, url: doc.fileURL!, group: "Notes")   // as each doc opens
//      Tabberwocky.shared.fillForTab = { _, url, _ in groups.color(forURL: url) }
//      Tabberwocky.shared.start(reapplyOn: [TabberwockyGroups.didChange])
//      // from your sidebar:
//      groups.toggle(group.id)        // collapse/expand the group's list (sidebar only)
//      groups.assign(url, to: id)     // move a doc to a group (recolors its tab)
//      groups.select(url)             // jump to a doc's tab
//      groups.addGroup("Drafts")
//

import AppKit

@MainActor
public final class TabberwockyGroups: ObservableObject {
    /// Posted after any change (assign / addGroup / toggle / register). Wire it into
    /// `Tabberwocky.shared.start(reapplyOn:)` so tab colors re-apply.
    public static let didChange = Notification.Name("TabberwockyGroupsChanged")

    public struct Group: Identifiable, Equatable {
        public let id = UUID()
        public var name: String
        public var color: NSColor
        /// Whether the group is expanded. Collapsing a group HIDES its tabs from the
        /// bar (their windows are parked off-screen in the shadow window) and collapses
        /// its file list in the sidebar; expanding restores both, in order.
        public var expanded: Bool = true
        public internal(set) var docs: [URL] = []     // member document URLs, in order
        public static func == (a: Group, b: Group) -> Bool { a.id == b.id }
    }

    /// The shared tabbing identifier all registered windows get (one native group).
    public let tabbingIdentifier: String
    @Published public private(set) var groups: [Group] = []

    /// When true, `apply()` logs the full window / tab-group topology to NSLog (prefix
    /// "🪟 TWGroups"), visible in Console.app. Off by default; flip it on while
    /// debugging collapse / expand ordering. See `dumpTopology(_:)`.
    public static var debugLogging = false

    private func dbg(_ message: String) {
        guard Self.debugLogging else { return }
        NSLog("%@", message)
    }

    private var windowForURL: [String: NSWindow] = [:]
    private var anchor: NSWindow?           // first registered window (group root)
    private var lastRegistered: NSWindow?   // chain new tabs after this, in order
    private var willCloseObserver: NSObjectProtocol?

    /// Off-screen, transparent host for collapsed tabs. Collapsed document windows
    /// are moved into THIS window's tab group, so they leave the visible bar while
    /// staying validly tabbed (no homeless windows → no pop-out singlets).
    private var _shadowWindow: NSWindow?
    private var shadowWindow: NSWindow {
        if let w = _shadowWindow { return w }
        let w = makeShadowWindow()
        _shadowWindow = w
        return w
    }
    private func makeShadowWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 480, height: 320),
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        // A DIFFERENT tabbing identifier so AppKit never auto-merges this into the
        // visible bar (same-id auto-tabbing pulled it in as a stray blank tab).
        // Explicit addTabbedWindow still parks docs here regardless of identifier.
        w.tabbingMode = .preferred
        w.tabbingIdentifier = tabbingIdentifier + "-shadow"
        w.alphaValue = 0
        w.isExcludedFromWindowsMenu = true
        // CRITICAL: NSWindow defaults isReleasedWhenClosed = true. If the OS ever
        // releases this window (close, app teardown, tab-group churn) while our
        // lazy strong ref still points at it, the next access dangles and crashes
        // in objc_retain. We own its lifetime, so opt out of auto-release.
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone]
        w.orderFront(nil)   // live tab host, but off-screen + transparent → invisible
        return w
    }

    private let palette: [NSColor] = [
        NSColor(red: 0.20, green: 0.62, blue: 0.70, alpha: 1),  // teal
        NSColor(red: 0.55, green: 0.45, blue: 0.95, alpha: 1),  // purple
        NSColor(red: 0.95, green: 0.55, blue: 0.25, alpha: 1),  // orange
        NSColor(red: 0.36, green: 0.74, blue: 0.42, alpha: 1),  // green
        NSColor(red: 0.93, green: 0.40, blue: 0.62, alpha: 1),  // pink
    ]

    public init(tabbingIdentifier: String = "TabberwockyGroup") {
        self.tabbingIdentifier = tabbingIdentifier
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
    /// tabbing identifier and tabs the window into the single group, in order.
    public func register(_ window: NSWindow, url: URL, group name: String, color: NSColor? = nil) {
        let url = norm(url)
        window.tabbingIdentifier = tabbingIdentifier
        if let last = lastRegistered {
            last.addTabbedWindow(window, ordered: .above)   // chain after the previous tab
        } else {
            anchor = window
            window.makeKeyAndOrderFront(nil)
        }
        lastRegistered = window
        windowForURL[url.absoluteString] = window
        let id = ensureGroup(name, color: color)
        if let i = groups.firstIndex(where: { $0.id == id }) { groups[i].docs.append(url) }
        changed()
    }

    /// Remove a closed window from all state.
    private func windowWillClose(_ window: NSWindow?) {
        guard let window else { return }
        let staleKeys = windowForURL.filter { $0.value === window }.map(\.key)
        guard !staleKeys.isEmpty else { return }
        for key in staleKeys {
            windowForURL.removeValue(forKey: key)
            for i in groups.indices { groups[i].docs.removeAll { $0.absoluteString == key } }
        }
        if anchor === window { anchor = windowForURL.values.first }
        if lastRegistered === window { lastRegistered = windowForURL.values.first }
        changed()
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

    /// Collapse / expand a group: collapsed groups' windows are parked in the shadow
    /// window (hidden); expanded groups' windows live in the visible window. The
    /// visible tabs are never re-tabbed, so collapsing one group doesn't disturb the
    /// others. Collapsing the only-open group expands the rest (so a header click is
    /// never a dead no-op).
    public func toggle(_ id: UUID) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        dbg("🪟 TWGroups TOGGLE group=\"\(groups[i].name)\" wasExpanded=\(groups[i].expanded)")
        if groups[i].expanded && groups.filter({ $0.expanded }).count <= 1 {
            for j in groups.indices { groups[j].expanded = true }
        } else {
            groups[i].expanded.toggle()
        }
        apply()
        changed()
    }

    /// Move a document into a group (recolors its tab; also re-homes it if the target
    /// group is collapsed/expanded).
    public func assign(_ url: URL, to groupID: UUID) {
        let url = norm(url)
        guard let target = groups.firstIndex(where: { $0.id == groupID }) else { return }
        for i in groups.indices { groups[i].docs.removeAll { $0 == url } }
        groups[target].docs.append(url)
        apply(select: url)
        changed()
    }

    /// Create a new (empty) group; returns its id.
    @discardableResult
    public func addGroup(_ name: String, color: NSColor? = nil) -> UUID {
        let id = ensureGroup(name, color: color)
        changed()
        return id
    }

    /// Reconcile window homes with each group's expanded flag using the shadow
    /// window. Only windows that need to move are touched — visible tabs that should
    /// stay visible (and hidden ones already parked) are left alone, so there's no
    /// flashing of the tabs that aren't changing.
    public func apply(select preferURL: URL? = nil) {
        dumpTopology("apply BEFORE")
        let visible = groups.filter { $0.expanded }.flatMap(\.docs).compactMap { windowForURL[$0.absoluteString] }
        let hidden  = groups.filter { !$0.expanded }.flatMap(\.docs).compactMap { windowForURL[$0.absoluteString] }
        guard !visible.isEmpty else { return }   // never blank the app
        dbg("🪟 TWGroups apply: visible=[\(visible.map { label($0) }.joined(separator: ","))] "
            + "hidden=[\(hidden.map { label($0) }.joined(separator: ","))] "
            + "preferURL=\(preferURL?.lastPathComponent ?? "nil")")

        // The shadow group (if the shadow window exists yet). Parked windows live here
        // while collapsed; it is never a valid visible host.
        let shadowGroup = _shadowWindow?.tabGroup
        func isReal(_ g: NSWindowTabGroup?) -> Bool { g != nil && g !== shadowGroup }

        // The tab we want fronted. Prefer an explicit request, else the current key
        // window — but only if it survives visible.
        let prefer = preferURL.flatMap { windowForURL[norm($0).absoluteString] }
        let desired = [prefer, NSApp.keyWindow].compactMap { $0 }.first { visible.contains($0) } ?? visible[0]

        // 1. Choose the TARGET visible group with minimal disturbance: the real group
        //    that already holds the window we're keeping active. Keeping that group put
        //    means already-visible tabs never move — so they never flash "active" as
        //    other tabs animate in (the bug we're fixing). If no visible window lives in
        //    a real group yet (everything was parked), evacuate the first one to seed
        //    one.
        if !visible.contains(where: { isReal($0.tabGroup) }) {
            shadowGroup?.removeWindow(visible[0])   // detach from shadow → standalone seed
        }
        let targetGroup = isReal(desired.tabGroup) ? desired.tabGroup
                                                   : visible.first { isReal($0.tabGroup) }?.tabGroup
        // First visible window already living in the target group — the anchor we insert
        // leading (out-of-group) windows BEFORE.
        let firstInTarget = visible.first { $0.tabGroup === targetGroup }

        // 2. Walk model order. Windows already in the target group are LEFT IN PLACE (no
        //    move, no flash); only windows that are elsewhere (parked, or in a second
        //    group) are inserted at their correct slot. This restores canonical order
        //    while moving the minimum number of tabs.
        var prev: NSWindow? = nil
        for window in visible {
            if window.tabGroup === targetGroup {
                prev = window                                   // in place; becomes the anchor
            } else {
                if let p = prev {
                    p.addTabbedWindow(window, ordered: .above)  // insert right after prev
                } else if let f = firstInTarget {
                    f.addTabbedWindow(window, ordered: .below)  // leading insert: before first existing
                }
                prev = window
            }
        }

        // 3. Select the surviving visible tab BEFORE parking anything.
        desired.tabGroup?.selectedWindow = desired
        desired.makeKeyAndOrderFront(nil)

        // 4. Park collapsed windows in the shadow group (off-screen → hidden). They
        //    stay TABBED inside the shadow (one group, count = 1 + parked docs) so
        //    macOS can't resurface them as lone floating singlets — the whole point of
        //    the shadow. We must NOT orderOut the docs: orderOut detaches a window from
        //    its tab group, scattering them into standalone singlets.
        if !hidden.isEmpty {
            shadowWindow.orderFront(nil)               // realize off-screen host
            for window in hidden where window.tabGroup !== shadowWindow.tabGroup {
                shadowWindow.addTabbedWindow(window, ordered: .above)
            }
            // Make the invisible, off-screen shadow window the group's SELECTED + front
            // member. A tab group only displays its selected window, and fronting the
            // off-screen shadow forces every other (non-selected) doc to hide — this
            // clears the "previously-active parked tab lingers on screen" glitch
            // without detaching anything from the group.
            shadowWindow.tabGroup?.selectedWindow = shadowWindow
            shadowWindow.orderFront(nil)
        }

        // 5. Defensive: the shadow window must never sit in the visible bar. If a prior
        //    state pulled it into the target group, eject it.
        if let sw = _shadowWindow, sw.tabGroup === desired.tabGroup {
            desired.tabGroup?.removeWindow(sw)
        }

        // 6. Re-assert the real front window (parking churn can steal key).
        desired.tabGroup?.selectedWindow = desired
        desired.makeKeyAndOrderFront(nil)
        dumpTopology("apply AFTER (desired=\(label(desired)))")
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

    // MARK: Debug

    /// Stable short id per NSWindow (object address) so a window can be tracked across
    /// dumps even as its title / position changes.
    private func shortID(_ w: NSWindow) -> String {
        let addr = UInt(bitPattern: ObjectIdentifier(w).hashValue)
        return String(format: "w%04X", addr & 0xFFFF)
    }

    /// Reverse-lookup the registered URL (filename) for a window, or a marker.
    private func label(_ w: NSWindow) -> String {
        if w === shadowWindowIfRealized { return "SHADOW🔴" }
        if let key = windowForURL.first(where: { $0.value === w })?.key,
           let name = URL(string: key)?.lastPathComponent { return name }
        return w.title.isEmpty ? "(untitled)" : w.title
    }

    /// Dump every native tab group and its members in order. Marks selected (▶),
    /// key (★), visible-on-screen (👁), and which group each member belongs to.
    public func dumpTopology(_ phase: String) {
        guard Self.debugLogging else { return }
        var lines = ["🪟 TWGroups [\(phase)]"]
        // Model side: what each group THINKS it holds.
        for g in groups {
            let mark = g.expanded ? "▽" : "▷"
            let docs = g.docs.map { $0.lastPathComponent }.joined(separator: ", ")
            lines.append("  \(mark) group \"\(g.name)\" expanded=\(g.expanded) docs=[\(docs)]")
        }
        // AppKit side: actual native tab groups, de-duplicated by identity.
        var seen = Set<ObjectIdentifier>()
        for w in NSApp.windows {
            guard let tg = w.tabGroup else { continue }
            let gid = ObjectIdentifier(tg)
            if seen.contains(gid) { continue }
            seen.insert(gid)
            let containsShadow = tg.windows.contains { $0 === shadowWindowIfRealized }
            lines.append("  ── tabGroup \(containsShadow ? "(SHADOW host)" : "(visible)") count=\(tg.windows.count)")
            for (i, member) in tg.windows.enumerated() {
                let sel = tg.selectedWindow === member ? "▶" : " "
                let key = member.isKeyWindow ? "★" : " "
                let vis = (member.isVisible && member.occlusionState.contains(.visible)) ? "👁" : "  "
                lines.append("       \(sel)\(key)\(vis) [\(i)] \(shortID(member)) \(label(member))")
            }
        }
        // Windows with NO tab group (homeless → would pop out as singlets).
        for w in NSApp.windows where w.tabGroup == nil {
            if windowForURL.values.contains(where: { $0 === w }) {
                lines.append("  ⚠️ HOMELESS (no tab group): \(shortID(w)) \(label(w))")
            }
        }
        dbg(lines.joined(separator: "\n"))
    }

    /// Non-forcing accessor — returns the shadow window only if it was already created,
    /// so debug labeling never accidentally realizes it.
    private var shadowWindowIfRealized: NSWindow? { _shadowWindow }

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
