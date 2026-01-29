import SwiftUI

@main
struct PortLightApp: App {
    @State private var connectionManager = ConnectionManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(manager: connectionManager)
        } label: {
            Image(systemName: connectionManager.menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Window("Manage Connections", id: "manage-connections") {
            ManageConnectionsView(configManager: connectionManager.configManager)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
