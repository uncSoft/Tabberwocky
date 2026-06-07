import SwiftUI
import AppKit

extension Notification.Name {
    /// Posted when the showcase theme changes so the tab styler re-applies.
    static let showcaseThemeChanged = Notification.Name("showcaseThemeChanged")
}

private func ns(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(red: r, green: g, blue: b, alpha: a)
}

/// The showcase's theme. Drives both the SwiftUI editor and the native tab styler.
/// The "bold" themes (Ocean, Sunset, Rainbow) demonstrate that the tab fill takes
/// any color/alpha — Rainbow even gives every tab its own distinct fill.
@MainActor
final class ShowcaseTheme: ObservableObject {
    static let shared = ShowcaseTheme()

    enum Mode: String, CaseIterable, Identifiable {
        case dark = "Dark", light = "Light", midnight = "Midnight"
        case ocean = "Ocean", sunset = "Sunset", rainbow = "Rainbow"
        var id: String { rawValue }
    }

    @Published var mode: Mode = .rainbow {
        didSet {
            applyAppearance()
            NotificationCenter.default.post(name: .showcaseThemeChanged, object: nil)
        }
    }

    var isLight: Bool { mode == .light }

    /// Sync AppKit's appearance so window chrome + SwiftUI controls match.
    func applyAppearance() {
        NSApp.appearance = NSAppearance(named: isLight ? .aqua : .darkAqua)
    }

    // MARK: Bar + accent
    var accentNS: NSColor {
        switch mode {
        case .light:   return .controlAccentColor
        case .ocean:   return ns(0.30, 0.82, 0.95)
        case .sunset:  return ns(1.00, 0.50, 0.58)
        case .rainbow: return .white
        default:       return ns(0.25, 0.62, 1.0)
        }
    }
    var barNS: NSColor {
        switch mode {
        case .dark:     return ns(0.11, 0.12, 0.15)   // #1c1f26
        case .light:    return .windowBackgroundColor
        case .midnight: return .black
        case .ocean:    return ns(0.04, 0.09, 0.13)
        case .sunset:   return ns(0.12, 0.06, 0.09)
        case .rainbow:  return ns(0.06, 0.06, 0.07)
        }
    }

    // MARK: Per-tab fill (this is the "fully color the fill" demo)
    private let rainbow: [NSColor] = [
        ns(0.95, 0.30, 0.32), ns(0.98, 0.56, 0.20), ns(0.95, 0.80, 0.22),
        ns(0.36, 0.80, 0.42), ns(0.20, 0.76, 0.76), ns(0.30, 0.56, 0.96),
        ns(0.58, 0.46, 0.96), ns(0.82, 0.40, 0.86)
    ]

    func tabFillNS(index: Int, active: Bool) -> NSColor {
        switch mode {
        case .dark, .midnight:
            return NSColor.white.withAlphaComponent(active ? 0.12 : 0.04)
        case .light:
            return active ? NSColor.white.withAlphaComponent(0.95)
                          : NSColor.black.withAlphaComponent(0.04)
        case .ocean:
            return ns(0.10, 0.55, 0.72).withAlphaComponent(active ? 0.90 : 0.32)
        case .sunset:
            return ns(1.0, 0.45, 0.48).withAlphaComponent(active ? 0.90 : 0.32)
        case .rainbow:
            return rainbow[index % rainbow.count].withAlphaComponent(active ? 0.95 : 0.55)
        }
    }

    /// Active tab gets an outline; bold themes lift it with white, others with accent.
    func tabOutlineNS(active: Bool) -> NSColor? {
        guard active else { return nil }
        switch mode {
        case .ocean, .sunset, .rainbow: return NSColor.white.withAlphaComponent(0.85)
        default:                        return accentNS
        }
    }

    func tabTextNS(active: Bool) -> NSColor {
        switch mode {
        case .light:
            return NSColor.black.withAlphaComponent(active ? 1.0 : 0.5)
        case .ocean, .sunset, .rainbow:
            return NSColor.white.withAlphaComponent(active ? 1.0 : 0.8)   // readable on saturated fills
        default:
            return active ? accentNS : NSColor.white.withAlphaComponent(0.55)
        }
    }

    // MARK: Editor (SwiftUI) colors
    var editorBackground: Color { Color(nsColor: barNS) }
    var editorText: Color { isLight ? .black : .white }
    var accent: Color { Color(nsColor: accentNS) }
}
