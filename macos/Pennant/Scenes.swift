import FeatureCore
import PennantKit
import Setup
import Shell
import SwiftUI

/// A main window: its state, kept across relaunches per window with `@SceneStorage` (the route and its history, the
/// inspector, the sidebar and its open departments; SWIFTUI_REBUILD.md section 3.1).
struct MainWindowScene: View {
    @SceneStorage("pennant.history") private var historyData = Data()
    @SceneStorage("pennant.inspector") private var inspectorPresented = false
    @SceneStorage("pennant.sidebarVisible") private var sidebarVisible = true
    @SceneStorage("pennant.expanded") private var expanded = ""
    @State private var window: MainWindowModel?

    var body: some View {
        Group {
            if let window {
                MainWindowView(window: window)
                    .onChange(of: window.historyStorage) { _, data in historyData = data }
                    .onChange(of: window.inspectorPresented) { _, shown in inspectorPresented = shown }
                    .onChange(of: window.sidebarVisibleStorage) { _, shown in sidebarVisible = shown }
                    .onChange(of: window.expandedStorage) { _, ids in expanded = ids }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .onAppear {
            guard window == nil else { return }
            window = MainWindowModel.restore(
                registry: AppRegistry.shared,
                history: historyData,
                inspectorPresented: inspectorPresented,
                sidebarVisible: sidebarVisible,
                expanded: expanded
            )
        }
    }
}

/// The Setup window: the steps, fed the served status (kept current by the event stream), started again at the save
/// step whenever something asks for it (Club ▸ Import Export…, Settings ▸ Choose Save…).
struct SetupScene: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouting.self) private var routing
    @State private var setup: SetupModel?

    var body: some View {
        Group {
            if let setup, model.isReady {
                SetupView(model: setup, status: model.status)
            } else {
                ServerStateView()
            }
        }
        .frame(width: SetupView.size.width, height: SetupView.size.height)
        .onAppear {
            guard setup == nil else { return }
            let model = model
            setup = SetupModel(client: { model.client }, onClubSaved: { await model.reloadAll() })
        }
        .onChange(of: routing.setupRequest) {
            setup?.restart()
            Task { await setup?.load() }
        }
    }
}
