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
    let model = AppModel(configuration: AppConfiguration.server())
    private var terminating = false
    private var terminationSignal: (any DispatchSourceSignal)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminationSignal = Self.quitOnTerminationSignal()
        Task { await model.start() }
    }

    /// SIGTERM (a `kill`, a script) quits like ⌘Q, so the server is stopped cleanly rather than orphaned. The
    /// handler is not main-actor code (it runs on a background queue); it starts the quit from the main run loop
    /// rather than from a main-queue block, because `.terminateLater` waits in a nested run loop that must still
    /// drain the main queue, where the clean stop runs.
    nonisolated private static func quitOnTerminationSignal() -> any DispatchSourceSignal {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global(qos: .userInitiated))
        source.setEventHandler {
            let mainLoop = CFRunLoopGetMain()
            CFRunLoopPerformBlock(mainLoop, CFRunLoopMode.commonModes.rawValue) {
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
            CFRunLoopWakeUp(mainLoop)
        }
        source.resume()
        return source
    }

    /// Quit waits for the server: SIGTERM, up to 5 seconds, then SIGKILL (SWIFTUI_REBUILD.md section 5.3).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateLater }
        terminating = true
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
