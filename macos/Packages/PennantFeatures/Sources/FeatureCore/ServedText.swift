import Foundation
import PennantAPI

/// Served values made ready to show, without adding anything the server did not say.
public enum ServedText {
    /// The toolbar's subtitle: how current the data is, from served values only (SWIFTUI_REBUILD.md section 3.2).
    /// The imported export's game date and the data status's own headline, joined; without a data status, the last
    /// import's time; else nothing. Never a judgment of its own ("stale", "fresh"). Game dates are shown as served.
    public nonisolated static func subtitle(
        dataStatus: Components.Schemas.DataStatus?,
        status: Components.Schemas.ServerStatus?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String? {
        if let dataStatus {
            let parts = [dataStatus.csv.currentDate, dataStatus.freshness.headline]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: " · ") }
        }
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
