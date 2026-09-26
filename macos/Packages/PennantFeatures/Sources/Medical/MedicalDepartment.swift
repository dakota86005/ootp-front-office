import FeatureCore
import PennantKit
import SwiftUI

/// Medical (SWIFTUI_REBUILD.md section 3.5). Every view is a structural placeholder until its milestone builds it.
public enum MedicalDepartment: DepartmentModule {
    public static let id: DeptID = "medical"
    public static let title: LocalizedStringResource = "Medical"
    public static let symbol = "cross.case"
    public static let order = 7
    public static let views: [DepartmentViewDescriptor] = [
        .placeholder(id: "report", title: "Report", symbol: "list.bullet.clipboard", keywords: ["health"]),
        .placeholder(id: "injuryReport", title: "Injury Report", symbol: "bandage", keywords: ["injuries", "injured list"]),
    ]
}
