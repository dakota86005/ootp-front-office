import XCTest

/// Smoke flows on the real app, its bundled server and a scratch data folder with the synthetic league
/// (`macos/scripts/test.sh` sets it up and passes `PENNANT_DEV_DATA_DIR` through `TEST_RUNNER_`). Without a scratch
/// folder the tests skip: they never launch the app on the real data folder. Screenshots are kept as attachments,
/// which `test.sh` extracts.
final class PennantUITests: XCTestCase {
    /// The scratch data folder the app runs on; never the real one.
    private var dataFolder: String {
        ProcessInfo.processInfo.environment["PENNANT_DEV_DATA_DIR"] ?? ""
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        if dataFolder.isEmpty {
            throw XCTSkip("PENNANT_DEV_DATA_DIR is not set: the UI tests run only on a scratch data folder (macos/scripts/test.sh)")
        }
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PENNANT_DEV_DATA_DIR"] = dataFolder
        if let logs = ProcessInfo.processInfo.environment["PENNANT_DEV_LOG_DIR"] {
            app.launchEnvironment["PENNANT_DEV_LOG_DIR"] = logs
        }
        app.launch()
        return app
    }

    @MainActor
    private func keep(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testStartsTheServerAndQuitsCleanly() throws {
        let app = launch()
        let ready = app.descendants(matching: .any)["server.ready"]
        let problem = app.descendants(matching: .any)["server.problem"]
        let deadline = Date.now.addingTimeInterval(60)
        while !ready.exists && !problem.exists && Date.now < deadline {
            _ = ready.waitForExistence(timeout: 1)
        }
        keep(app.windows.firstMatch.screenshot(), named: "main-window-server-state")
        XCTAssertFalse(problem.exists, "the server did not start; see the log in the scratch data folder")
        XCTAssertTrue(ready.exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(dataFolder)/server.lock"))

        // Quit waits for the server to stop, which releases the data-folder lock
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 20))
        XCTAssertFalse(FileManager.default.fileExists(atPath: "\(dataFolder)/server.lock"))
    }
}
