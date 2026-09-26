import FeatureCore
import PennantKit
import SwiftUI

/// Finance (SWIFTUI_REBUILD.md section 3.5). Every view is a structural placeholder until its milestone builds it.
public enum FinanceDepartment: DepartmentModule {
    public static let id: DeptID = "finance"
    public static let title: LocalizedStringResource = "Finance"
    public static let symbol = "dollarsign.circle"
    public static let order = 6
    public static let views: [DepartmentViewDescriptor] = [
        .placeholder(id: "report", title: "Report", symbol: "list.bullet.clipboard", keywords: ["money"]),
        .placeholder(id: "payrollBudget", title: "Payroll & Budget", symbol: "banknote", keywords: ["payroll", "budget"]),
        .placeholder(id: "contracts", title: "Contracts", symbol: "doc.text", keywords: ["salaries"]),
        .placeholder(id: "freeAgents", title: "Free Agents", symbol: "person.badge.plus", keywords: ["free agency", "signings"]),
        .placeholder(id: "horizonBoard", title: "Horizon Board", symbol: "calendar.day.timeline.left", keywords: ["control", "future seasons"]),
    ]
}
