import FeatureCore
import Foundation
import PennantKit
import Shell
import Testing

private let morning = AppRoute(department: "frontOffice", view: "morningReport")
private let lineup = AppRoute(department: "majorLeague", view: "lineup")
private let prospects = AppRoute(department: "farm", view: "prospects")
private let wire = AppRoute(department: "league", view: "wire")

@Suite("Back and Forward")
struct NavigationHistoryTests {
    @Test("going somewhere puts the current route on Back and clears Forward")
    func goPushes() {
        var history = NavigationHistory(current: morning)
        #expect(!history.canGoBack && !history.canGoForward)
        history.go(to: lineup)
        history.go(to: prospects)
        #expect(history.current == prospects)
        #expect(history.back == [morning, lineup])
        let moved1 = history.goBack()
        #expect(moved1)
        #expect(history.current == lineup)
        #expect(history.forward == [prospects])
        history.go(to: wire)
        #expect(history.forward.isEmpty)
        #expect(history.back == [morning, lineup])
    }

    @Test("Back then Forward returns to where the window was")
    func backForward() {
        var history = NavigationHistory(current: morning)
        history.go(to: lineup)
        history.go(to: prospects)
        let moved2 = history.goBack()
        #expect(moved2)
        let moved3 = history.goBack()
        #expect(moved3)
        #expect(history.current == morning)
        let moved4 = history.goBack()
        #expect(!moved4)
        #expect(history.current == morning)
        let moved5 = history.goForward()
        #expect(moved5)
        let moved6 = history.goForward()
        #expect(moved6)
        #expect(history.current == prospects)
        let moved7 = history.goForward()
        #expect(!moved7)
    }

    @Test("going to where the window already is changes nothing")
    func sameRoute() {
        var history = NavigationHistory(current: morning)
        history.go(to: lineup)
        history.goBack()
        history.go(to: morning)
        #expect(history.back.isEmpty)
        #expect(history.forward == [lineup])
    }

    @Test("Back keeps at most its limit")
    func limit() {
        var history = NavigationHistory(current: morning)
        for index in 0..<(NavigationHistory.limit + 10) {
            history.go(to: AppRoute(department: "majorLeague", view: "view\(index)"))
        }
        #expect(history.back.count == NavigationHistory.limit)
    }

    @Test("survives the round trip through scene storage")
    func roundTrip() throws {
        var history = NavigationHistory(current: morning)
        history.go(to: lineup)
        history.go(to: prospects)
        history.goBack()
        let restored = try #require(NavigationHistory.restored(from: history.restorationData))
        #expect(restored == history)
        #expect(NavigationHistory.restored(from: Data()) == nil)
        #expect(NavigationHistory.restored(from: Data("not json".utf8)) == nil)
    }
}

@MainActor
@Suite("A main window's state")
struct MainWindowModelTests {
    let registry = DepartmentRegistry(allDepartments)

    @Test("starts on the first department's first view with it open in the sidebar")
    func defaults() {
        let window = MainWindowModel(registry: registry)
        #expect(window.route == morning)
        #expect(window.expanded == ["frontOffice"])
        #expect(!window.inspectorPresented)
        #expect(window.sidebarVisibleStorage)
    }

    @Test("selecting in the sidebar, Go and ⌘-numbers move it, and Back and Forward follow")
    func navigates() {
        let window = MainWindowModel(registry: registry)
        window.selection = lineup
        #expect(window.route == lineup)
        #expect(window.expanded.contains("majorLeague"))
        window.go(toShortcut: 3)
        #expect(window.route == AppRoute(department: "farm", view: "report"))
        window.go(toDepartment: "league")
        #expect(window.route == wire)
        window.goBack()
        window.goBack()
        #expect(window.route == lineup)
        #expect(window.canGoForward)
        window.goForward()
        #expect(window.route.department == "farm")
    }

    @Test("ignores a route this build does not know")
    func ignoresUnknown() {
        let window = MainWindowModel(registry: registry)
        window.go(to: AppRoute(department: "stadium", view: "seats"))
        #expect(window.route == morning)
        #expect(!window.canGoBack)
    }

    @Test("restores its route, history, inspector, sidebar and open departments from scene storage")
    func restoration() {
        let window = MainWindowModel(registry: registry)
        window.go(to: lineup)
        window.go(to: prospects)
        window.inspectorPresented = true
        window.sidebarVisibility = .detailOnly
        window.expanded.insert("scouting")
        let restored = MainWindowModel.restore(
            registry: registry,
            history: window.historyStorage,
            inspectorPresented: window.inspectorPresented,
            sidebarVisible: window.sidebarVisibleStorage,
            expanded: window.expandedStorage
        )
        #expect(restored.route == prospects)
        #expect(restored.history == window.history)
        #expect(restored.inspectorPresented)
        #expect(!restored.sidebarVisibleStorage)
        #expect(restored.expanded == window.expanded)
    }

    @Test("a restored route a newer build saved falls back to the default, and its unknown entries are dropped")
    func restorationOfUnknown() {
        var saved = NavigationHistory(current: lineup)
        saved.go(to: AppRoute(department: "stadium", view: "seats"))
        let restored = MainWindowModel.restore(
            registry: registry, history: saved.restorationData, inspectorPresented: false, sidebarVisible: true,
            expanded: "majorLeague,stadium"
        )
        #expect(restored.route == morning)
        #expect(restored.history.back == [lineup])
        #expect(restored.expanded == ["majorLeague", "frontOffice"])
        let empty = MainWindowModel.restore(
            registry: registry, history: Data(), inspectorPresented: false, sidebarVisible: true, expanded: ""
        )
        #expect(empty.route == morning)
    }
}
