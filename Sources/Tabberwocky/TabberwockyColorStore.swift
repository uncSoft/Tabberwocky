//
//  TabberwockyColorStore.swift
//  Optional, drop-in persistence for per-tab colors.
//
//  This file is independent of Tabberwocky.swift — include it only if you want
//  ready-made persistence. It saves per-document fill and label colors to
//  UserDefaults, keyed by file URL, so a tab keeps its color across launches.
//
//  Easiest possible integration:
//
//      let colors = TabberwockyColorStore()
//      colors.attach()                                   // wires fill + label hooks
//      Tabberwocky.shared.style = { … }
//      Tabberwocky.shared.start(reapplyOn: [TabberwockyColorStore.colorsChanged])
//
//      // when the user picks a color for a document:
//      colors.setColor(.systemTeal, for: doc.fileURL, .fill)
//
//  Or compose it yourself (keep your own rainbow / tag logic) by reading
//  `colors.color(for:_:)` inside your own `fillForTab` / `textForTab`.
//

import AppKit

public final class TabberwockyColorStore {
    /// Which part of the tab a stored color applies to.
    public enum Role: String { case fill, label }

    /// Posted after any change, so you can re-apply styling:
    /// `Tabberwocky.shared.start(reapplyOn: [TabberwockyColorStore.colorsChanged])`.
    public static let colorsChanged = Notification.Name("TabberwockyColorsChanged")

    private let defaults: UserDefaults
    private let storageKey: String
    private var cache: [String: NSColor] = [:]

    /// - Parameters:
    ///   - defaults: where to persist (default `.standard`).
    ///   - storageKey: the UserDefaults key to store under (override if you keep
    ///     several independent sets, or to namespace per app).
    public init(defaults: UserDefaults = .standard, storageKey: String = "TabberwockyColors") {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    // MARK: Read / write

    public func color(for url: URL?, _ role: Role) -> NSColor? {
        guard let key = key(url, role) else { return nil }
        return cache[key]
    }

    /// Set (or clear, with `nil`) a color for a document. Persists immediately and
    /// posts `colorsChanged`.
    public func setColor(_ color: NSColor?, for url: URL?, _ role: Role) {
        guard let key = key(url, role) else { return }
        if let color { cache[key] = color } else { cache.removeValue(forKey: key) }
        save()
        NotificationCenter.default.post(name: Self.colorsChanged, object: nil)
    }

    /// Remove every stored color.
    public func clearAll() {
        cache.removeAll()
        save()
        NotificationCenter.default.post(name: Self.colorsChanged, object: nil)
    }

    // MARK: One-call wiring

    /// Point Tabberwocky's `fillForTab` / `textForTab` at this store. Use when the
    /// stored colors are the *only* source of per-tab color. If you also do rainbow
    /// / tag / etc., skip this and read `color(for:_:)` inside your own closures.
    public func attach(to tabberwocky: Tabberwocky = .shared) {
        tabberwocky.fillForTab = { [weak self] _, url, _ in self?.color(for: url, .fill) }
        tabberwocky.textForTab = { [weak self] _, url, _ in self?.color(for: url, .label) }
    }

    // MARK: Storage

    private func key(_ url: URL?, _ role: Role) -> String? {
        guard let s = url?.absoluteString else { return nil }
        return "\(s)#\(role.rawValue)"
    }

    private func load() {
        guard let dict = defaults.dictionary(forKey: storageKey) as? [String: Data] else { return }
        for (key, data) in dict {
            if let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
                cache[key] = color
            }
        }
    }

    private func save() {
        var dict: [String: Data] = [:]
        for (key, color) in cache {
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: color,
                                                            requiringSecureCoding: true) {
                dict[key] = data
            }
        }
        defaults.set(dict, forKey: storageKey)
    }
}
