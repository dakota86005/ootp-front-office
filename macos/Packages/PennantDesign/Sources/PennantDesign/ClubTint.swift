import SwiftUI

/// A club's colours as the server serves them (`colors` on `/api/orgs`), ready to draw: the fill, and text that stays
/// readable on it. A colour the server did not serve is never invented.
///
/// Readability follows WCAG's contrast ratio: 4.5:1 normally, 7:1 when the GM has turned on Increase Contrast. The
/// club's own foreground is used when it reads on the served fill; else black or white, whichever reads; and when
/// neither does, or no fill is served, or the GM turned team colours off (the served `useTeamColors`), the card is
/// neutral: the system's fill with the primary text colour, never white on the accent. This is drawing, not a judgment
/// about the club; the palette itself moves server-side with `derivePalette` (SWIFTUI_REBUILD.md section 3.7).
nonisolated public struct ClubTint: Sendable, Equatable {
    /// The served background (`bg`), as `#rrggbb`; nil when none was served.
    public var background: String?
    /// The served foreground (`fg`).
    public var foreground: String?
    /// The served secondary colour.
    public var secondary: String?
    /// The served preference to draw team colours (`useTeamColors`); false draws the card neutral.
    public var useTeamColors: Bool

    public init(background: String?, foreground: String?, secondary: String? = nil, useTeamColors: Bool = true) {
        self.background = background
        self.foreground = foreground
        self.secondary = secondary
        self.useTeamColors = useTeamColors
    }

    /// The contrast ratio the text needs on the fill.
    public static func requiredContrast(increased: Bool) -> Double { increased ? 7 : 4.5 }

    /// How to draw the card.
    public enum TextChoice: Sendable, Equatable {
        /// The served fill with the club's own foreground, which reads well enough.
        case served
        /// The served fill with black text.
        case black
        /// The served fill with white text.
        case white
        /// No club colour: the system fill with the primary text colour.
        case neutral
    }

    /// The drawing for the needed contrast.
    public func textChoice(increasedContrast: Bool) -> TextChoice {
        guard useTeamColors, let fill = ServedColor.components(background) else { return .neutral }
        let needed = Self.requiredContrast(increased: increasedContrast)
        if let text = ServedColor.components(foreground), Self.contrast(fill, text) >= needed {
            return .served
        }
        let onBlack = Self.contrast(fill, (0, 0, 0))
        let onWhite = Self.contrast(fill, (1, 1, 1))
        if max(onBlack, onWhite) < needed { return .neutral }
        return onBlack >= onWhite ? .black : .white
    }

    /// The served fill's colour, or nil when the card is neutral.
    public func fill(increasedContrast: Bool) -> Color? {
        textChoice(increasedContrast: increasedContrast) == .neutral ? nil : ServedColor.color(background)
    }

    /// The text colour on the served fill, or nil when the card is neutral (the primary style).
    public func text(increasedContrast: Bool) -> Color? {
        switch textChoice(increasedContrast: increasedContrast) {
        case .served: ServedColor.color(foreground)
        case .black: .black
        case .white: .white
        case .neutral: nil
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
