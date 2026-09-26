import FeatureCore
import PennantKit
import SwiftUI

/// Front Office (SWIFTUI_REBUILD.md section 3.5). Every view is a structural placeholder until its milestone builds it.
public enum FrontOfficeDepartment: DepartmentModule {
    public static let id: DeptID = "frontOffice"
    public static let title: LocalizedStringResource = "Front Office"
    public static let symbol = "building.2"
    public static let order = 1
    public static let views: [DepartmentViewDescriptor] = [
        .placeholder(id: "morningReport", title: "Morning Report", symbol: "sun.horizon", keywords: ["today", "summary", "record", "desk"]),
        .placeholder(id: "storylines", title: "Storylines", symbol: "text.book.closed", keywords: ["stories", "ai"]),
        .placeholder(id: "briefing", title: "GM Briefing", symbol: "doc.richtext", keywords: ["briefing", "ai"]),
    ]
}
