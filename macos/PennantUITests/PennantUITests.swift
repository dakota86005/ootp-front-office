import XCTest

/// Smoke flows on the real app, its bundled server and scratch data folders holding the synthetic league
/// (SWIFTUI_REBUILD.md section 8). `macos/scripts/test.sh` passes, through `TEST_RUNNER_`, a scratch folder
/// (`PENNANT_UI_SCRATCH`) and the synthetic league (`PENNANT_UI_LEAGUE`); each test copies the league into a fresh data
/// folder of its own there. Without them the tests skip: they never launch the app on the real data folder.
/// Screenshots are kept as attachments, which `test.sh` extracts.
final class PennantUITests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var scratch: URL!
    private var dataFolder: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let root = environment["PENNANT_UI_SCRATCH"], let league = environment["PENNANT_UI_LEAGUE"] else {
            throw XCTSkip("PENNANT_UI_SCRATCH and PENNANT_UI_LEAGUE are not set: the UI tests run only on scratch data folders (macos/scripts/test.sh)")
        }
        scratch = URL(fileURLWithPath: root).appending(path: "\(name.filter(\.isLetter))-\(UUID().uuidString.prefix(6))", directoryHint: .isDirectory)
        dataFolder = scratch.appending(path: "data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: league), to: dataFolder.appending(path: "league.db"))
    }

    // MARK: Helpers

    /// A pretend OOTP save in the scratch folder: the `.lg` folder with an export of one small table.
    private func makeSave() throws -> URL {
        let save = scratch.appending(path: "saves/Synthetic League.lg", directoryHint: .isDirectory)
        let csv = save.appending(path: "import_export/csv", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: csv, withIntermediateDirectories: true)
        try Data("id,note\n1,one\n2,two\n".utf8).write(to: csv.appending(path: "zz_ui_check.csv"))
        return save
    }

    /// Chooses the pretend save for the server before the app starts (the server's own `config.json`), so the app
    /// opens on a configured save.
    private func configureSave() throws {
        let csv = try makeSave().appending(path: "import_export/csv")
        let config = ["csvDir": csv.path(percentEncoded: false), "saveName": "Synthetic League"]
        try JSONSerialization.data(withJSONObject: config).write(to: dataFolder.appending(path: "config.json"))
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["PENNANT_DEV_DATA_DIR"] = dataFolder.path(percentEncoded: false)
        app.launchEnvironment["PENNANT_DEV_LOG_DIR"] = scratch.appending(path: "logs").path(percentEncoded: false)
        // A fresh window each time: no restored route from an earlier run
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Waits for the main window's shell (the sidebar) or a server problem; fails on a problem.
    @MainActor
    private func waitForShell(_ app: XCUIApplication) {
        let sidebar = element(app, "sidebar")
        let problem = element(app, "server.problem")
        let deadline = Date.now.addingTimeInterval(60)
        while !sidebar.exists && !problem.exists && Date.now < deadline {
            _ = sidebar.waitForExistence(timeout: 1)
        }
        XCTAssertFalse(problem.exists, "the server did not start; see \(scratch.path)/logs/server.log")
        XCTAssertTrue(sidebar.exists)
    }

    @MainActor
    private func keep(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func quitCleanly(_ app: XCUIApplication) {
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 20))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataFolder.appending(path: "server.lock").path))
    }

    // MARK: Flows

    @MainActor
    func testStartsTheServerAndQuitsCleanly() throws {
        try configureSave()
        let app = launch()
        waitForShell(app)
        keep(app.windows.firstMatch.screenshot(), named: "main-window")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataFolder.appending(path: "server.lock").path))
        quitCleanly(app)
    }

    /// First run: the server has no save, so Setup opens by itself. A folder is picked by path, the import runs, and
    /// a club is saved; Setup closes and the main window shows the club.
    @MainActor
    func testSetupFlowOnAScratchFolder() throws {
        let save = try makeSave()
        let app = launch()
        let setup = element(app, "setup")
        XCTAssertTrue(setup.waitForExistence(timeout: 60), "Setup did not open for a server with no save")
        keep(app.windows.firstMatch.screenshot(), named: "setup-find-save")

        let path = element(app, "setup.folderPath")
        path.click()
        path.typeText(save.path(percentEncoded: false))
        element(app, "setup.useFolder").click()

        let clubs = element(app, "setup.clubs")
        XCTAssertTrue(clubs.waitForExistence(timeout: 60), "the import did not reach the club step")
        keep(app.windows.firstMatch.screenshot(), named: "setup-pick-club")
        element(app, "setup.saveClub").click()

        XCTAssertTrue(setup.waitForNonExistence(timeout: 20), "Setup did not close after the club was saved")
        waitForShell(app)
        XCTAssertTrue(element(app, "club.card").waitForExistence(timeout: 10))
        keep(app.windows.firstMatch.screenshot(), named: "main-window-after-setup")
        quitCleanly(app)
    }

    /// Every department by ⌘1 to ⌘9 and through the sidebar, Back and Forward, the inspector, Settings' tabs, and an
    /// accessibility audit.
    @MainActor
    func testDepartmentsInspectorAndSettings() throws {
        try configureSave()
        let app = launch()
        waitForShell(app)

        let departments: [(key: String, id: String, first: String, last: String)] = [
            ("1", "frontOffice", "morningReport", "briefing"),
            ("2", "majorLeague", "report", "seasonTrends"),
            ("3", "farm", "report", "decision"),
            ("4", "scouting", "draftBoard", "playerSearch"),
            ("5", "trades", "tradeDesk", "tradeDesk"),
            ("6", "finance", "report", "horizonBoard"),
            ("7", "medical", "report", "injuryReport"),
            ("8", "league", "wire", "franchiseHistory"),
            ("9", "philosophy", "organizationalPhilosophy", "coachingStaff"),
        ]
        for department in departments {
            app.typeKey(department.key, modifierFlags: .command)
            XCTAssertTrue(element(app, "detail.\(department.id).\(department.first)").waitForExistence(timeout: 5),
                          "⌘\(department.key) did not open \(department.id)")
            let row = element(app, "sidebar.\(department.id).\(department.last)")
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.click()
            XCTAssertTrue(element(app, "detail.\(department.id).\(department.last)").waitForExistence(timeout: 5))
            keep(app.windows.firstMatch.screenshot(), named: "department-\(department.id)")
        }

        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(element(app, "detail.philosophy.organizationalPhilosophy").waitForExistence(timeout: 5))
        app.typeKey("]", modifierFlags: .command)
        XCTAssertTrue(element(app, "detail.philosophy.coachingStaff").waitForExistence(timeout: 5))

        app.typeKey("i", modifierFlags: [.command, .option])
        XCTAssertTrue(element(app, "inspector").waitForExistence(timeout: 5))
        keep(app.windows.firstMatch.screenshot(), named: "inspector-open")
        app.typeKey("i", modifierFlags: [.command, .option])
        XCTAssertTrue(element(app, "inspector").waitForNonExistence(timeout: 5))

        try app.performAccessibilityAudit()

        app.typeKey(",", modifierFlags: .command)
        for (tab, identifier) in [("General", "settings.general"), ("Appearance", "settings.appearance"), ("AI", "settings.ai")] {
            let button = app.toolbars.buttons[tab].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "no \(tab) tab")
            button.click()
            XCTAssertTrue(element(app, identifier).waitForExistence(timeout: 5))
            keep(app.windows.firstMatch.screenshot(), named: "settings-\(tab.lowercased())")
        }
        app.typeKey("w", modifierFlags: .command)
        quitCleanly(app)
    }
}
