import Foundation

/// Formatting for a served number that arrives without its own display string. Rare by design: a value the GM
/// reads carries the server's `display` (D-056), and the app formats only plain counts such as an import's rows.
/// It never rounds a judgment into being, and a missing number is never shown as zero.
public enum ServedFormat {
    /// A count with the reader's grouping (`12,480`); nil stays nil, for the view to show the served sentence.
    public static func count(_ value: Int?, locale: Locale = .current) -> String? {
        value.map { $0.formatted(.number.grouping(.automatic).locale(locale)) }
    }

    /// A share of a whole as a whole percent (`42%`), for a progress bar's label; nil when the whole is unknown or
    /// empty.
    public static func share(_ part: Int?, of whole: Int?, locale: Locale = .current) -> String? {
        guard let part, let whole, whole > 0 else { return nil }
        return (Double(part) / Double(whole)).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }
}
