import AppKit
import FeatureCore
import Shell
import Testing

/// Every view title in the registry fits the sidebar at its narrowest, at the default text size, so none is cut short
/// ("Schedule & Game Pl…"). The row text size and the room a row needs beside its title are the sidebar's own
/// (`SidebarView`), measured from the snapshots.
@MainActor
@Suite("The sidebar's width")
struct SidebarWidthTests {
    let registry = DepartmentRegistry(allDepartments)

    @Test("fits every view and department title at the default text size")
    func titlesFit() {
        let font = NSFont.systemFont(ofSize: SidebarView.rowTextSize)
        var widest = ("", CGFloat(0))
        for department in registry.departments {
            for title in [department.title] + department.views.map(\.title) {
                let text = String(localized: title)
                let width = (text as NSString).size(withAttributes: [.font: font]).width
                if width > widest.1 { widest = (text, width) }
            }
        }
        #expect(widest.1 + SidebarView.viewRowInset <= SidebarView.minimumWidth, "\(widest.0) needs \(widest.1 + SidebarView.viewRowInset) pt")
        #expect(SidebarView.minimumWidth <= SidebarView.idealWidth)
        #expect(SidebarView.idealWidth <= SidebarView.maximumWidth)
    }
}
