import PennantKit
import SwiftUI

/// A department as the registry holds it: the module's answers, read once.
public struct Department: Identifiable, Sendable {
    public let id: DeptID
    public let title: LocalizedStringResource
    public let symbol: String
    public let order: Int
    public let views: [DepartmentViewDescriptor]
    private let badgeReader: @MainActor @Sendable (AppModel) -> Int?

    init(_ module: any DepartmentModule.Type) {
        id = module.id
        title = module.title
        symbol = module.symbol
        order = module.order
        views = module.views
        badgeReader = { module.badge(from: $0) }
    }

    /// The route to the department's first view (where Go takes the GM).
    public var firstRoute: AppRoute? { views.first.map { AppRoute(department: id, view: $0.id) } }

    public func route(to view: DepartmentViewDescriptor) -> AppRoute { AppRoute(department: id, view: view.id) }

    /// The sidebar badge's count, or nil for none.
    @MainActor public func badge(from model: AppModel) -> Int? { badgeReader(model) }
}

/// Every department, in order (SWIFTUI_REBUILD.md section 6). The app target assembles it from the modules; the
/// sidebar, the Go menu's ⌘1 to ⌘9 and the default route come from it.
public struct DepartmentRegistry: Sendable {
    public let departments: [Department]

    public init(_ modules: [any DepartmentModule.Type]) {
        departments = modules.map(Department.init).sorted { $0.order < $1.order }
    }

    public func department(_ id: DeptID) -> Department? { departments.first { $0.id == id } }

    /// The descriptor a route names, or nil for a route this build does not know (saved by a newer one).
    public func descriptor(for route: AppRoute) -> DepartmentViewDescriptor? {
        department(route.department)?.views.first { $0.id == route.view }
    }

    public func contains(_ route: AppRoute) -> Bool { descriptor(for: route) != nil }

    /// Where a new window opens: the first department's first view.
    public var defaultRoute: AppRoute {
        departments.lazy.compactMap(\.firstRoute).first ?? AppRoute(department: "frontOffice", view: "morningReport")
    }

    /// A restored route when this build knows it, else the default.
    public func resolve(_ route: AppRoute?) -> AppRoute {
        if let route, contains(route) { route } else { defaultRoute }
    }

    /// The departments Go reaches with ⌘1 to ⌘9: the first nine in order, numbered from 1.
    public var shortcutDepartments: [(number: Int, department: Department)] {
        departments.prefix(9).enumerated().map { (number: $0.offset + 1, department: $0.element) }
    }

    /// Where ⌘`number` goes: the department's first view; nil outside 1...9 or past the last department.
    public func route(forShortcut number: Int) -> AppRoute? {
        shortcutDepartments.first { $0.number == number }?.department.firstRoute
    }

    /// What is wrong with the assembled registry (duplicate ids or orders, a department with no views); empty when
    /// it is sound. The app checks it in Debug builds and the tests check it always.
    public var problems: [String] {
        var found: [String] = []
        var ids = Set<DeptID>()
        var orders = Set<Int>()
        for department in departments {
            if !ids.insert(department.id).inserted { found.append("duplicate department id \(department.id.rawValue)") }
            if !orders.insert(department.order).inserted { found.append("duplicate order \(department.order)") }
            if department.views.isEmpty { found.append("\(department.id.rawValue) has no views") }
            var viewIDs = Set<String>()
            for view in department.views where !viewIDs.insert(view.id).inserted {
                found.append("duplicate view id \(department.id.rawValue).\(view.id)")
            }
        }
        return found
    }
}
