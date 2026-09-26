import FeatureCore
import PennantDesign
import PennantKit
import SwiftUI

/// The sidebar (SWIFTUI_REBUILD.md section 3.2): the club card, then every department from the registry disclosing its
/// views (two levels, the HIG's most), with SF Symbols and a badge when a department serves a count (from N7).
public struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Bindable var window: MainWindowModel

    /// The sidebar column's widths: wide enough that every view title in the registry fits at the default text size
    /// (checked by `SidebarWidthTests`).
    public static let minimumWidth: CGFloat = 270
    public static let idealWidth: CGFloat = 280
    public static let maximumWidth: CGFloat = 380
    /// What a view row needs beside its title (the disclosure indent, the symbol and the margins), and the sidebar's row
    /// text size at the default setting, both as macOS 26 draws them (measured from the snapshots).
    public static let viewRowInset: CGFloat = 92
    public static let rowTextSize: CGFloat = 15

    public init(window: MainWindowModel) {
        self.window = window
    }

    public var body: some View {
        List(selection: $window.selection) {
            ForEach(window.registry.departments) { department in
                let served = model.catalog?.departments.first { $0.id.value2 == department.id.rawValue || $0.id.value1?.rawValue == department.id.rawValue }
                DisclosureGroup(isExpanded: window.isExpanded(department.id)) {
                    ForEach(department.views) { view in
                        Label {
                            // The served name; the structural title only while the catalog is not there
                            if let name = served?.views.first(where: { $0.id == view.id })?.name {
                                Text(verbatim: name)
                            } else {
                                Text(view.title)
                            }
                        } icon: {
                            Image(systemName: view.symbol)
                        }
                        .tag(department.route(to: view))
                        .accessibilityIdentifier("sidebar.\(department.id.rawValue).\(view.id)")
                    }
                } label: {
                    Label {
                        if let name = served?.name { Text(verbatim: name) } else { Text(department.title) }
                    } icon: {
                        Image(systemName: department.symbol)
                    }
                    .badge(department.badge(from: model) ?? 0)
                    .accessibilityIdentifier("sidebar.\(department.id.rawValue)")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarClubCard()
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .accessibilityIdentifier("sidebar")
    }
}

/// The club card for the served current club: its served name and colours (unless the GM turned team colours off, the
/// served `useTeamColors`), its record and logo from the catalog, and which club it is. A configured club the club
/// list does not have is named as not found; with no club served there is no card.
struct SidebarClubCard: View {
    @Environment(AppModel.self) private var model
    @State private var logo: Image?

    var body: some View {
        if let club = model.club {
            if let org = club.org {
                let served = model.catalogClub
                ClubCard(
                    name: org.label,
                    detail: club.source.label,
                    record: served?.record.display,
                    recordHint: served?.record.hint,
                    logo: logo,
                    tint: ClubTint(
                        background: org.colors.bg,
                        foreground: org.colors.fg,
                        secondary: org.colors.secondary,
                        useTeamColors: model.settings?.settings.useTeamColors ?? true
                    )
                )
                .task(id: served?.logo) { await loadLogo(served?.logo) }
            } else {
                Label("Club not in this save", systemImage: "questionmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("club.card")
            }
        }
    }
}

extension SidebarClubCard {
    /// The club's logo from the path the catalog serves (the save's own art); none when the save holds none.
    private func loadLogo(_ path: String?) async {
        guard let path, let data = await model.servedFile(path), let image = NSImage(data: data) else {
            logo = nil
            return
        }
        logo = Image(nsImage: image)
    }
}

extension CurrentClub.Source {
    /// A structural line saying which club this is.
    var label: Text? {
        switch self {
        case .humanManaged: Text("Your club")
        case .configured: Text("Chosen in Settings")
        case .other: nil
        }
    }
}
