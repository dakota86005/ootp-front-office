import FeatureCore
import PennantKit
import SwiftUI

/// Trades (SWIFTUI_REBUILD.md section 3.5). Every view is a structural placeholder until its milestone builds it.
public enum TradesDepartment: DepartmentModule {
    public static let id: DeptID = "trades"
    public static let title: LocalizedStringResource = "Trades"
    public static let symbol = "arrow.left.arrow.right.circle"
    public static let order = 5
    public static let views: [DepartmentViewDescriptor] = [
        .placeholder(id: "tradeDesk", title: "Trade Desk", symbol: "arrow.triangle.swap", keywords: ["offers", "builder", "analysis", "league fits"]),
    ]
}
