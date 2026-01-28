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
    }
}
