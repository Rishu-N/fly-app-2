import SwiftUI
import UIKit
import PlannerCore

// Design tokens for "Chronograph bones, Aurora light" (see docs/research/ui-1 + ui-2).
// Compiled into both the app and the widget extension.

// MARK: - Colour helpers

extension Color {
    /// Dynamic light/dark colour from two hex literals (0xRRGGBB).
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: opacity))
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

// MARK: - Themes ("dials")

enum DialTheme: String, CaseIterable, Identifiable, Codable {
    case aurora, lume, ember

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aurora: "Aurora"
        case .lume: "Lume"
        case .ember: "Ember"
        }
    }

    var palette: Palette {
        switch self {
        case .aurora: .aurora
        case .lume: .lume
        case .ember: .ember
        }
    }

    static var stored: DialTheme {
        DialTheme(rawValue: AppGroup.defaults.string(forKey: AppGroup.themeKey) ?? "") ?? .aurora
    }
}

struct Palette {
    let bg: Color
    let surface: Color
    let surface2: Color
    let separator: Color
    let ringTrack: Color
    let text1: Color
    let text2: Color
    let text3: Color
    /// The "now" accent — only ever used for live things.
    let now: Color
    let onNow: Color
    let nowSoft: Color
    let success: Color
    let warning: Color
    let danger: Color

    static let aurora = Palette(
        bg: Color(light: 0xF5F5FA, dark: 0x0A0B11),
        surface: Color(light: 0xFFFFFF, dark: 0x15161F),
        surface2: Color(light: 0xECECF3, dark: 0x1F202C),
        separator: Color(light: 0xDEDEE8, dark: 0x2A2B39),
        ringTrack: Color(light: 0xE4E4EE, dark: 0x23243A),
        text1: Color(light: 0x15141C, dark: 0xF4F3FA),
        text2: Color(light: 0x4F4D5E, dark: 0xB5B3C7),
        text3: Color(light: 0x67657A, dark: 0x8E8CA3),
        now: Color(light: 0x5B3DF5, dark: 0x9483FF),
        onNow: Color(light: 0xFFFFFF, dark: 0x0A0B11),
        nowSoft: Color(light: 0xECE8FF, dark: 0x231D4D),
        success: Color(light: 0x177A45, dark: 0x3DD68C),
        warning: Color(light: 0x965700, dark: 0xFFB547),
        danger: Color(light: 0xC92A37, dark: 0xFF6166)
    )

    static let lume = Palette(
        bg: Color(light: 0xF3F4F6, dark: 0x060708),
        surface: Color(light: 0xFFFFFF, dark: 0x111316),
        surface2: Color(light: 0xE8EAEE, dark: 0x1A1D21),
        separator: Color(light: 0xD3D7DD, dark: 0x2A2E35),
        ringTrack: Color(light: 0xE1E4E8, dark: 0x1E2227),
        text1: Color(light: 0x0B0D10, dark: 0xF4F6F8),
        text2: Color(light: 0x4A515B, dark: 0xA3AAB4),
        text3: Color(light: 0x686F7A, dark: 0x7C838E),
        now: Color(light: 0x00748C, dark: 0x3DE3F5),
        onNow: Color(light: 0xFFFFFF, dark: 0x00242B),
        nowSoft: Color(light: 0xD6EEF2, dark: 0x0B2A30),
        success: Color(light: 0x127A3A, dark: 0x3DDC84),
        warning: Color(light: 0xA35C00, dark: 0xFFB020),
        danger: Color(light: 0xCC1D35, dark: 0xFF4D5E)
    )

    static let ember = Palette(
        bg: Color(light: 0xF5F2EE, dark: 0x0B0A09),
        surface: Color(light: 0xFFFFFF, dark: 0x161412),
        surface2: Color(light: 0xEBE6E0, dark: 0x201D1A),
        separator: Color(light: 0xD8D1C9, dark: 0x302B27),
        ringTrack: Color(light: 0xE6E0D9, dark: 0x241F1B),
        text1: Color(light: 0x14110E, dark: 0xF7F3EE),
        text2: Color(light: 0x57504A, dark: 0xB1A99F),
        text3: Color(light: 0x726A62, dark: 0x857D74),
        now: Color(light: 0xBA3C04, dark: 0xFF6A2B),
        onNow: Color(light: 0xFFFFFF, dark: 0x1F0A00),
        nowSoft: Color(light: 0xFBE3D6, dark: 0x3A1A0C),
        success: Color(light: 0x1C7D45, dark: 0x4BD68A),
        warning: Color(light: 0x8A6400, dark: 0xFFD23F),
        danger: Color(light: 0xC4164C, dark: 0xFF4577)
    )
}

// MARK: - Category colours (shared by every theme so user data never changes hue)

extension TaskCategory {
    var color: Color {
        switch self {
        case .focus: Color(light: 0x4C5BD4, dark: 0x8B96FF)    // Indigo
        case .meeting: Color(light: 0x1A7FD1, dark: 0x5CB8FF)  // Sky
        case .learning: Color(light: 0x0E8C80, dark: 0x3FD4C2) // Teal
        case .health: Color(light: 0x2E8F47, dark: 0x66D682)   // Green
        case .admin: Color(light: 0xB87A00, dark: 0xFFC53D)    // Amber
        case .social: Color(light: 0xE0560F, dark: 0xFF8A4C)   // Coral
        case .personal: Color(light: 0xD2336D, dark: 0xFF78A9) // Rose
        case .rest: Color(light: 0x5B6472, dark: 0xA3ACB9)     // Slate
        }
    }

    /// Bright variant used on always-black surfaces (Dynamic Island).
    var islandColor: Color {
        switch self {
        case .focus: Color(hex: 0x8B96FF)
        case .meeting: Color(hex: 0x5CB8FF)
        case .learning: Color(hex: 0x3FD4C2)
        case .health: Color(hex: 0x66D682)
        case .admin: Color(hex: 0xFFC53D)
        case .social: Color(hex: 0xFF8A4C)
        case .personal: Color(hex: 0xFF78A9)
        case .rest: Color(hex: 0xA3ACB9)
        }
    }
}

// MARK: - Time-of-day ambient field (UI-2 §2.6)

enum DayPhase: CaseIterable {
    case dawn, day, dusk, night

    static func at(_ date: Date, calendar: Calendar = .current) -> DayPhase {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        switch minutes {
        case 300..<540: return .dawn      // 05:00–09:00
        case 540..<990: return .day       // 09:00–16:30
        case 990..<1230: return .dusk     // 16:30–20:30
        default: return .night
        }
    }

    /// Four stops: top-leading, top-trailing, centre/bottom-trailing, bottom-leading.
    func stops(dark: Bool) -> [Color] {
        let hexes: [UInt32]
        switch (self, dark) {
        case (.dawn, false): hexes = [0xFFE4D4, 0xFFD3DE, 0xE6DDFF, 0xFFF5E3]
        case (.day, false): hexes = [0xDCEBFF, 0xE2F6F2, 0xFFF5D9, 0xF0EDFF]
        case (.dusk, false): hexes = [0xFFDAC4, 0xF8CBE1, 0xDCCFFF, 0xFFE9CF]
        case (.night, false): hexes = [0xDDE1FF, 0xE7DCFF, 0xD3E4F4, 0xF1EFFA]
        case (.dawn, true): hexes = [0x2B1B3E, 0x46223A, 0x3B2A20, 0x12131D]
        case (.day, true): hexes = [0x0F2A45, 0x0D3638, 0x1E2050, 0x0B0C12]
        case (.dusk, true): hexes = [0x3A1D47, 0x552338, 0x47290F, 0x140F1C]
        case (.night, true): hexes = [0x0B1131, 0x1B1347, 0x06292E, 0x08090F]
        }
        return hexes.map { Color(hex: $0) }
    }
}

// MARK: - Typography

enum TypeRamp {
    /// Hero timer digits: condensed, light, monospaced digits.
    static func timer(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light).width(.condensed).monospacedDigit()
    }

    static let cardTitle = Font.system(.title, weight: .semibold)
    static let rowTitle = Font.system(.headline, weight: .semibold)
    static let timeLabel = Font.system(.subheadline, weight: .medium).monospacedDigit()
    static let meta = Font.system(.footnote)
    /// Uppercase, expanded "bezel" eyebrow — the signature detail. Pair with `.tracking(1)`.
    static let eyebrow = Font.system(size: 11, weight: .semibold).width(.expanded)
    static let tick = Font.system(size: 11, weight: .medium, design: .monospaced)
}

struct Eyebrow: View {
    let text: String
    var color: Color? = nil
    @Environment(\.palette) private var palette

    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(TypeRamp.eyebrow)
            .tracking(1)
            .foregroundStyle(color ?? palette.text2)
    }
}

// MARK: - Motion tokens (everything ≤ 350 ms except the conveyor)

enum Motion {
    static let micro = Animation.snappy(duration: 0.15)
    static let snappy = Animation.snappy(duration: 0.25)
    static let bouncy = Animation.spring(response: 0.32, dampingFraction: 0.72)
    static let glide = Animation.spring(response: 0.35, dampingFraction: 0.86)
    static let conveyor = Animation.spring(response: 0.36, dampingFraction: 0.86)
    static let fade = Animation.easeInOut(duration: 0.2)

    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }
}

// MARK: - Environment

private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Palette = .aurora
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Glass (iOS 26 Liquid Glass with a material fallback)

extension View {
    /// Floating-layer surface: Liquid Glass on iOS 26, regular material + hairline earlier.
    @ViewBuilder
    func floatingGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        // Xcode 26+ SDK: real Liquid Glass on iOS 26, material fallback below.
        if #available(iOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            materialFallback(shape)
        }
        #else
        // Older SDKs (Xcode 16) don't have the glass APIs at all.
        materialFallback(shape)
        #endif
    }

    private func materialFallback<S: Shape>(_ shape: S) -> some View {
        self
            .background(.regularMaterial, in: shape)
            .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}
