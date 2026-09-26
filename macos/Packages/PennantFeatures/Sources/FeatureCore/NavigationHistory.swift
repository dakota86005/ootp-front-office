import Foundation
import PennantKit

/// A main window's Back and Forward (SWIFTUI_REBUILD.md section 3.6: Back ⌘[, Forward ⌘]): the routes before the
/// current one and those after it, as a browser keeps them. Going somewhere new clears Forward; going to where the
/// window already is changes nothing.
public nonisolated struct NavigationHistory: Codable, Hashable, Sendable {
    public private(set) var back: [AppRoute]
    public private(set) var current: AppRoute
    public private(set) var forward: [AppRoute]

    /// How many routes Back keeps.
    public static let limit = 50

    public init(current: AppRoute, back: [AppRoute] = [], forward: [AppRoute] = []) {
        self.current = current
        self.back = Array(back.suffix(Self.limit))
        self.forward = Array(forward.prefix(Self.limit))
    }

    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    /// Goes to `route`: the current route joins Back and Forward is cleared. Nothing happens when the window is
    /// already there.
    public mutating func go(to route: AppRoute) {
        guard route != current else { return }
        back.append(current)
        if back.count > Self.limit { back.removeFirst(back.count - Self.limit) }
        forward.removeAll()
        current = route
    }

    /// Back one route; false when there is none.
    @discardableResult
    public mutating func goBack() -> Bool {
        guard let previous = back.popLast() else { return false }
        forward.insert(current, at: 0)
        current = previous
        return true
    }

    /// Forward one route; false when there is none.
    @discardableResult
    public mutating func goForward() -> Bool {
        guard !forward.isEmpty else { return false }
        back.append(current)
        current = forward.removeFirst()
        return true
    }

    /// Drops every route `keep` rejects (a route a newer build saved), keeping `fallback` as the current route when the
    /// current one goes.
    public func filtered(keeping keep: (AppRoute) -> Bool, fallback: AppRoute) -> NavigationHistory {
        NavigationHistory(
            current: keep(current) ? current : fallback,
            back: back.filter(keep),
            forward: forward.filter(keep)
        )
    }

    // MARK: Scene restoration

    /// The history as `@SceneStorage` keeps it.
    public var restorationData: Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    /// A history restored from `@SceneStorage`, or nil when the data is empty or unreadable.
    public static func restored(from data: Data) -> NavigationHistory? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(NavigationHistory.self, from: data)
    }
}
