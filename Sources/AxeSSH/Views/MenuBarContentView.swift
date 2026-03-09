import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    @State private var alertMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            selectedConnectionSection

            Divider()
                .padding(.vertical, 6)

            Button {
                appState.prepareForCreate()
                openEditorWindow()
            } label: {
                Label("Add Connection", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.vertical, 6)

            Button("Settings") {
                openSettingsWindow()
            }
            .buttonStyle(.plain)
            .padding(.bottom,5)

            Button("About AxeSSH") {
                // Phase 1 placeholder
            }
            .buttonStyle(.plain)
            .padding(.bottom,5)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            
        }
        .padding(12)
        .frame(minWidth: 200)
        .alert("Action Failed", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    private var selectedConnectionSection: some View {
        if appState.profiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No connections saved")
                    .font(.headline)
                Text("Add Connection to get started")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {

                if let profile = appState.selectedProfile {
                    ConnectionCardView(
                        profile: profile,
                        onEdit: {
                            appState.prepareForEdit(profile)
                            openEditorWindow()
                        },
                        onConnect: {
                            do {
                                let resolved = try appState.resolveProfileCredentials(for: profile, reason: .terminalConnect)
                                try TerminalLauncher.connect(profile: resolved, preference: appState.settings.defaultTerminal)
                                appState.setStatus(.connected, forProfileID: profile.id)
                            } catch {
                                alertMessage = error.localizedDescription
                            }
                        },
                        onDisconnect: {
                            appState.setStatus(.disconnected, forProfileID: profile.id)
                            appState.clearRuntimeCredential(for: profile.id)
                        },
                        onBrowse: {
                            openFileBrowserWindow()
                        }
                    )
                }
            }
        }
    }

    private var selectedBinding: Binding<UUID?> {
        Binding(
            get: { appState.selectedProfileID },
            set: { appState.selectedProfileID = $0 }
        )
    }

    private func openEditorWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "profile-editor")
        // SwiftUI may create the window asynchronously; make it key once it exists so it accepts typing.
        for delay in [0.15, 0.4, 0.7] as [Double] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let editorWindow = NSApp.windows.first(where: { window in
                    window.identifier?.rawValue.contains("profile-editor") == true
                        || window.title == "Add Connection"
                        || window.title == "Edit Connection"
                }) else { return }
                NSApp.activate(ignoringOtherApps: true)
                editorWindow.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func openFileBrowserWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "file-browser")
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
        for delay in [0.15, 0.4, 0.7] as [Double] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let settingsWindow = NSApp.windows.first(where: { window in
                    window.identifier?.rawValue.contains("settings") == true
                        || window.title == "Settings"
                }) else { return }
                NSApp.activate(ignoringOtherApps: true)
                settingsWindow.makeKeyAndOrderFront(nil)
            }
        }
    }
}
