import Foundation
import PennantKit

/// Where this build's server and data are.
///
/// A release build always uses SWIFTUI_REBUILD.md section 5.3's folders: the data in
/// `~/Library/Application Support/ootp-front-office`, the log in `~/Library/Logs/Pennant`.
///
/// A Debug build (and the UI tests) can be pointed at a scratch data folder instead, so development never has to run
/// on the real one:
/// - `PENNANT_DEV_DATA_DIR=<folder>` in the environment, or the launch argument `-PennantDevDataFolder <folder>`;
/// - `PENNANT_DEV_LOG_DIR` / `-PennantDevLogFolder` for the log (default: `logs/` inside that data folder);
/// - `OOTP_FO_DB_READONLY=1` is passed on to the server, for opening a copy of a real save read-only.
/// Without an override a Debug build uses the release folders, like the Electron app on the same Mac.
enum AppConfiguration {
    static func server(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> ServerConfiguration {
        #if DEBUG
        if let data = environment["PENNANT_DEV_DATA_DIR"] ?? defaults.string(forKey: "PennantDevDataFolder"), !data.isEmpty {
            let dataFolder = folder(data)
            let logs = (environment["PENNANT_DEV_LOG_DIR"] ?? defaults.string(forKey: "PennantDevLogFolder"))
                .flatMap { $0.isEmpty ? nil : folder($0) }
                ?? dataFolder.appending(path: "logs", directoryHint: .isDirectory)
            var extra: [String: String] = [:]
            if let readOnly = environment["OOTP_FO_DB_READONLY"] { extra["OOTP_FO_DB_READONLY"] = readOnly }
            return .bundled(in: bundle, dataFolder: dataFolder, logFolder: logs, extraEnvironment: extra)
        }
        #endif
        return .bundled(in: bundle)
    }

    private static func folder(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }
}
