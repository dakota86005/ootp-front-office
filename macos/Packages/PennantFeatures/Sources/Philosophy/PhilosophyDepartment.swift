import FeatureCore
import PennantKit
import SwiftUI

/// Philosophy & Staff (SWIFTUI_REBUILD.md section 3.5). Every view is a structural placeholder until its milestone builds it.
public enum PhilosophyDepartment: DepartmentModule {
    public static let id: DeptID = "philosophy"
    public static let title: LocalizedStringResource = "Philosophy & Staff"
    public static let symbol = "slider.horizontal.3"
    public static let order = 9
    public static let views: [DepartmentViewDescriptor] = [
        .placeholder(id: "organizationalPhilosophy", title: "Organizational Philosophy", symbol: "scope", keywords: ["philosophy", "preferences"]),
        .placeholder(id: "coachingStaff", title: "Coaching Staff", symbol: "person.3.sequence", keywords: ["coaches", "staff"]),
    ]
}
