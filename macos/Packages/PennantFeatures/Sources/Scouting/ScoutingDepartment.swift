import FeatureCore
import PennantKit
import SwiftUI

/// Scouting (SWIFTUI_REBUILD.md section 3.5). Every view is a structural placeholder until its milestone builds it.
public enum ScoutingDepartment: DepartmentModule {
    public static let id: DeptID = "scouting"
    public static let title: LocalizedStringResource = "Scouting"
    public static let symbol = "binoculars"
    public static let order = 4
    public static let views: [DepartmentViewDescriptor] = [
        .placeholder(id: "draftBoard", title: "Draft Board", symbol: "list.star", keywords: ["draft", "amateur"]),
        .placeholder(id: "playerSearch", title: "Player Search", symbol: "magnifyingglass", keywords: ["find", "players"]),
    ]
}
