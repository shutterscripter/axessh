import SwiftUI

@main
struct AxeSSHApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("AxeSSH", systemImage: "terminal") {
            MenuBarContentView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "profile-editor") {
            ProfileEditorView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)

        WindowGroup("File Browser", id: "file-browser") {
            FileBrowserView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 640, height: 480)
    }
}
