import SwiftUI

/// A colour the server serves as a hex string (`#1d2d44`, a club's colours from `/api/orgs`). The app never invents
/// a club colour: a string that is not a colour reads as nil, and the view falls back to the system accent.
public enum ServedColor {
    /// The sRGB components of `#rgb` or `#rrggbb` (the `#` optional), each 0...1; nil for anything else.
    public nonisolated static func components(_ hex: String?) -> (red: Double, green: Double, blue: Double)? {
        guard var text = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// The colour, or nil when the served string is not one.
    public nonisolated static func color(_ hex: String?) -> Color? {
        components(hex).map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue) }
    }
}
