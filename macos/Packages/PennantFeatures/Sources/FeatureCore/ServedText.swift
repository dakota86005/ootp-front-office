import Foundation
import PennantAPI

/// Served values made ready to show, without adding anything the server did not say.
public enum ServedText {
    /// The toolbar's subtitle: how current the data is, as the server writes it (`subtitle` on `/api/v2/data-status`:
    /// the game date and the headline, SWIFTUI_REBUILD.md section 3.2). Before the data status arrives, the last
    /// import's time; else nothing. Never a judgment of its own ("stale", "fresh"), and never a game date parsed here.
    public nonisolated static func subtitle(
        dataStatus: Components.Schemas.DataStatusView?,
        status: Components.Schemas.ServerStatus?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String? {
        if let served = dataStatus?.subtitle.trimmingCharacters(in: .whitespaces), !served.isEmpty { return served }
        return timestamp(status?.lastImport?.finishedAt, locale: locale, timeZone: timeZone)
    }

    /// A served ISO 8601 timestamp (an import's or an export's time, never a game date) as the reader's date and
    /// time; a string that is not one is shown as served; nil stays nil.
    public nonisolated static func timestamp(_ served: String?, locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
        guard let served, !served.isEmpty else { return nil }
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        guard let date = (try? withFraction.parse(served)) ?? (try? Date.ISO8601FormatStyle().parse(served)) else {
            return served
        }
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}
