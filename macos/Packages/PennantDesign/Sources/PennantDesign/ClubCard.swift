import SwiftUI

/// The club card at the top of the sidebar (SWIFTUI_REBUILD.md section 3.2): the served club's name on its served
/// colours, with a line saying which club this is. Everything written on it comes from the caller: the name is
/// served, the line is a structural label.
///
/// The colour is never the only signal: the name is always written. With Increase Contrast the card gets a border and
/// its text is held to 7:1; it is opaque, so Reduce Transparency changes nothing, and it does not move.
public struct ClubCard: View {
    private let name: String
    private let detail: Text?
    private let tint: ClubTint
    private let symbol: String
    @Environment(\.colorSchemeContrast) private var contrast

    /// - Parameters:
    ///   - name: the served club name (`label`).
    ///   - detail: a structural line under it ("Your club"), or nil.
    ///   - tint: the served colours.
    ///   - symbol: an SF Symbol drawn beside the name.
    public init(name: String, detail: Text?, tint: ClubTint, symbol: String = "baseball.diamond.bases") {
        self.name = name
        self.detail = detail
        self.tint = tint
        self.symbol = symbol
    }

    public var body: some View {
        let increased = contrast == .increased
        let text = tint.text(increasedContrast: increased)
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(.headline)
                    .lineLimit(2)
                if let detail {
                    detail
                        .font(.caption)
                        .opacity(increased ? 1 : 0.85)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(text)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.fill, in: .rect(cornerRadius: 10))
        .overlay {
            if increased {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("club.card")
    }
}

#Preview("Club card") {
    VStack {
        ClubCard(name: "Club 1 N", detail: Text(verbatim: "Your club"), tint: ClubTint(background: "#1d2d44", foreground: "#f0ebd8"))
        ClubCard(name: "Low contrast", detail: nil, tint: ClubTint(background: "#777777", foreground: "#888888"))
        ClubCard(name: "No colours served", detail: nil, tint: ClubTint(background: nil, foreground: nil))
    }
    .padding()
    .frame(width: 260)
}
