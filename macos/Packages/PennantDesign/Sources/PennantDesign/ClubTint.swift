import SwiftUI

/// A club's colours as the server serves them (`colors` on `/api/orgs`), ready to draw: the fill, and text that stays
/// readable on it. A colour the server did not serve is never invented: without a served background the tint is the
/// system accent, and without a served foreground the text is whichever of black or white reads better.
///
/// Readability follows WCAG's contrast ratio: 4.5:1 normally, 7:1 when the GM has turned on Increase Contrast. When the
/// served foreground falls short on the served background, the text becomes black or white instead (the club's own
/// pair is kept whenever it reads). This is drawing, not a judgment about the club; the palette itself moves
/// server-side with `derivePalette` (SWIFTUI_REBUILD.md section 3.7).
nonisolated public struct ClubTint: Sendable, Equatable {
    /// The served background (`bg`), as `#rrggbb`; nil when none was served.
    public var background: String?
    /// The served foreground (`fg`).
    public var foreground: String?
    /// The served secondary colour.
    public var secondary: String?

    public init(background: String?, foreground: String?, secondary: String? = nil) {
        self.background = background
        self.foreground = foreground
        self.secondary = secondary
    }

    /// The contrast ratio the text needs on the fill.
    public static func requiredContrast(increased: Bool) -> Double { increased ? 7 : 4.5 }

    /// The fill: the served background, else the accent colour.
    public var fill: Color { ServedColor.color(background) ?? .accentColor }

    /// Whether a served background exists (so the card is in the club's colour rather than the accent's).
    public var hasServedFill: Bool { ServedColor.components(background) != nil }

    /// Which text to draw on the fill.
    public enum TextChoice: Sendable, Equatable {
        /// The club's own foreground reads well enough.
        case served
        case black
        case white
    }

    /// The text for the fill: the served foreground when it reads at the needed contrast, else black or white,
    /// whichever reads better. With no served background, white on the accent.
    public func textChoice(increasedContrast: Bool) -> TextChoice {
        guard let fill = ServedColor.components(background) else { return .white }
        let needed = Self.requiredContrast(increased: increasedContrast)
        if let text = ServedColor.components(foreground), Self.contrast(fill, text) >= needed {
            return .served
        }
        let onBlack = Self.contrast(fill, (0, 0, 0))
        let onWhite = Self.contrast(fill, (1, 1, 1))
        return onBlack >= onWhite ? .black : .white
    }

    /// The text colour for the fill.
    public func text(increasedContrast: Bool) -> Color {
        switch textChoice(increasedContrast: increasedContrast) {
        case .served: ServedColor.color(foreground) ?? .white
        case .black: .black
        case .white: .white
        }
    }

    // MARK: WCAG 2 contrast

    /// Relative luminance of an sRGB colour.
    public static func luminance(_ c: (red: Double, green: Double, blue: Double)) -> Double {
        func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)
    }

    /// The contrast ratio of two sRGB colours, 1...21.
    public static func contrast(
        _ a: (red: Double, green: Double, blue: Double),
        _ b: (red: Double, green: Double, blue: Double)
    ) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
