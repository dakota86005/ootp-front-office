#if DEBUG
import Foundation
import PennantAPI
import PennantKit

/// Models for `#Preview`s, fed by the payloads the real server sent on the synthetic save (`contract/fixtures/`),
/// read where they are in the repository (SWIFTUI_REBUILD.md section 8). Debug builds only.
enum PreviewModels {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "contract/fixtures/responses")

    private static func decode<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: fixtures.appending(path: "\(name).json")) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static var configuration: ServerConfiguration {
        .bundled(in: .main, dataFolder: URL(fileURLWithPath: "/tmp/ootp-fo-test", isDirectory: true))
    }

    @MainActor
    static func ready() -> AppModel {
        let status = decode(Components.Schemas.ServerStatus.self, "getStatus")
        let state: ServerState = status.map {
            .ready(ServerConnection(port: 5178, token: String(repeating: "p", count: 64), pid: 1, status: $0))
        } ?? .starting
        return .preview(
            configuration: configuration,
            state: state,
            status: status,
            settings: decode(Components.Schemas.SettingsResponse.self, "getSettings"),
            orgs: decode([Components.Schemas.Org].self, "listOrgs") ?? []
        )
    }
}
#endif
