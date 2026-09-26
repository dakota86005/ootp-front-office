import PennantKit
import SwiftUI

/// Pennant for Mac (D-055): the scenes. At N3 the main window shows the server's state; the window shell (sidebar,
/// toolbar, inspector, commands), Setup and Settings arrive in the next stage.
@main
struct PennantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(appDelegate.model)
                .frame(minWidth: 720, minHeight: 480)
        }
    }
}

/// Owns the app's model, starts the server when the app launches, and stops it cleanly before the app quits.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    private let quit: QuitCoordinator
    private var terminationSignal: (any DispatchSourceSignal)?

    override init() {
        let model = AppModel(configuration: AppConfiguration.server())
        let controller = model.serverController
        self.model = model
        quit = QuitCoordinator(prepare: { model.beginShutdown() }, stop: { await controller.stop() })
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminationSignal = Self.quitOnTerminationSignal()
        Task { await model.start() }
    }

    /// SIGTERM (a `kill`, a script) quits like ⌘Q, so the server is stopped cleanly rather than orphaned. The handler
    /// runs on a background queue and asks through `QuitCoordinator.requestQuit()`, the one way to quit.
    nonisolated private static func quitOnTerminationSignal() -> any DispatchSourceSignal {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global(qos: .userInitiated))
        source.setEventHandler { QuitCoordinator.requestQuit() }
        source.resume()
        return source
    }

    /// Quit waits for the server (SIGTERM, up to 5 seconds, then SIGKILL; SWIFTUI_REBUILD.md section 5.3), without
    /// depending on the main queue (`QuitCoordinator`).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quit.shouldTerminate { ok in NSApp.reply(toApplicationShouldTerminate: ok) }
    }
}
