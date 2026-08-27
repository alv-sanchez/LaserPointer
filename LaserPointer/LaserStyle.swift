//
//  LaserStyle.swift
//  LaserPointer
//
//  Every user-tunable knob, in one Codable-ish value type plus a UserDefaults
//  store. Kept deliberately separate from the controller so the renderer can
//  take a plain struct and stay free of any dependency on app state.
//

import AppKit

/// How a press is drawn.
enum LaserMode: String, CaseIterable, Identifiable {
    /// A stroke of ink that trails the cursor and fades away behind it.
    case trail
    /// Just the glowing dot under the cursor — no trail left behind.
    case dot

    var id: String { rawValue }

    var label: String {
        switch self {
        case .trail: return "Trail"
        case .dot:   return "Dot only"
        }
    }
}

/// The four beam colors. A fixed palette rather than an NSColorPicker on
/// purpose: these are the hues that stay legible when drawn as a thin
/// translucent glow on top of arbitrary slide content, and picking a dark
/// custom color is the one way to make the app look broken.
enum LaserColor: String, CaseIterable, Identifiable {
    case red, green, cyan, amber

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    /// The beam body. Values are deliberately hot (high saturation, high
    /// brightness) because the glow passes composite additively-ish over the
    /// slide underneath and anything darker reads as a smudge.
    var color: NSColor {
        switch self {
        case .red:   return NSColor(srgbRed: 1.00, green: 0.16, blue: 0.20, alpha: 1)
        case .green: return NSColor(srgbRed: 0.22, green: 1.00, blue: 0.38, alpha: 1)
        case .cyan:  return NSColor(srgbRed: 0.25, green: 0.83, blue: 1.00, alpha: 1)
        case .amber: return NSColor(srgbRed: 1.00, green: 0.76, blue: 0.16, alpha: 1)
        }
    }
}

struct LaserStyle {
    var mode: LaserMode = .trail
    var color: LaserColor = .red

    /// Beam width in points. 6 is about the apparent size of a real laser dot
    /// on a projected slide.
    var thickness: CGFloat = 6

    /// Seconds from a mark being laid down to it being fully invisible.
    var fade: TimeInterval = 1.2

    static let thicknessRange: ClosedRange<CGFloat> = 2...20
    static let fadeRange: ClosedRange<TimeInterval> = 0.25...5.0
}

// MARK: - Persistence

/// UserDefaults keys live here so a typo is a compile error somewhere rather
/// than a silently-never-restored setting.
enum StyleStore {
    private static let modeKey      = "laser.mode"
    private static let colorKey     = "laser.color"
    private static let thicknessKey = "laser.thickness"
    private static let fadeKey      = "laser.fade"

    static func load() -> LaserStyle {
        let d = UserDefaults.standard
        var style = LaserStyle()

        if let raw = d.string(forKey: modeKey), let mode = LaserMode(rawValue: raw) {
            style.mode = mode
        }
        if let raw = d.string(forKey: colorKey), let color = LaserColor(rawValue: raw) {
            style.color = color
        }
        // `object(forKey:)` rather than `double(forKey:)`: the latter returns 0
        // for a missing key, which would silently clamp a fresh install to the
        // minimum thickness and zero fade instead of using the defaults above.
        if let t = d.object(forKey: thicknessKey) as? Double {
            style.thickness = CGFloat(t).clamped(to: LaserStyle.thicknessRange)
        }
        if let f = d.object(forKey: fadeKey) as? Double {
            style.fade = f.clamped(to: LaserStyle.fadeRange)
        }
        return style
    }

    static func save(_ style: LaserStyle) {
        let d = UserDefaults.standard
        d.set(style.mode.rawValue, forKey: modeKey)
        d.set(style.color.rawValue, forKey: colorKey)
        d.set(Double(style.thickness), forKey: thicknessKey)
        d.set(style.fade, forKey: fadeKey)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
