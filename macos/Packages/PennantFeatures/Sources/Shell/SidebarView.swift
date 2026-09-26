import FeatureCore
import PennantDesign
import PennantKit
import SwiftUI

/// The sidebar (SWIFTUI_REBUILD.md section 3.2): the club card, then every department from the registry disclosing its
/// views (two levels, the HIG's most), with SF Symbols and a badge when a department serves a count (from N7).
public struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Bindable var window: MainWindowModel

    /// The sidebar column's ideal width.
    public static let idealWidth: CGFloat = 240

    public init(window: MainWindowModel) {
        self.window = window
    }

    public var body: some View {
        List(selection: $window.selection) {
            ForEach(window.registry.departments) { department in
                DisclosureGroup(isExpanded: window.isExpanded(department.id)) {
                    ForEach(department.views) { view in
                        Label {
                            Text(view.title)
                        } icon: {
                            Image(systemName: view.symbol)
                        }
                        .tag(department.route(to: view))
                        .accessibilityIdentifier("sidebar.\(department.id.rawValue).\(view.id)")
                    }
                } label: {
                    Label {
                        Text(department.title)
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

/// The club card for the served current club: its served name and colours, and which club it is. A configured club
/// the club list does not have is named as not found; with no club served there is no card.
struct SidebarClubCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let club = model.club {
            if let org = club.org {
                ClubCard(
                    name: org.label,
                    detail: club.source.label,
                    tint: ClubTint(background: org.colors.bg, foreground: org.colors.fg, secondary: org.colors.secondary)
                )
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
