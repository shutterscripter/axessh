import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var showResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
           
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom){
                    
                    
                    Picker("Default Terminal", selection: $appState.settings.defaultTerminal) {
                        ForEach(TerminalPreference.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
                

                
                Picker("Credential Storage", selection: $appState.settings.credentialStorage) {
                    ForEach(CredentialStoragePreference.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
             
                Toggle("Show Hidden Files", isOn: $appState.settings.showHiddenFiles)

                Picker("Upload Conflict Policy", selection: $appState.settings.uploadConflictPolicy) {
                    ForEach(UploadConflictPolicy.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("Download Folder")
                        .font(.subheadline)
                    Spacer()
                    Text(downloadFolderLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose") {
                        chooseDownloadFolder()
                    }
                    if !appState.settings.downloadFolderPath.isEmpty {
                        Button("Clear") {
                            appState.settings.downloadFolderPath = ""
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Launch at login", isOn: $appState.settings.launchAtLogin)
                
                Button("Reset App Data", role: .destructive) {
                    showResetConfirmation = true
                }
                .foregroundColor(.red)
                
                
            }
        }
        .padding(16)
        .frame(minWidth: 380)
        .confirmationDialog("Reset all app data?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                do {
                    try appState.resetAppData()
                } catch {
                    // Keep silent in this first settings pass; data store errors can be surfaced later.
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes profiles, recent private key history, and local cache.")
        }
        .background(
            SettingsWindowAccessor { window in
                guard let window else { return }
                window.level = .normal
                Task { @MainActor in bringSettingsWindowToFront(window) }
                for delay in [0.2, 0.5] as [Double] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        Task { @MainActor in bringSettingsWindowToFront(window) }
                    }
                }
            }
        )
        .onAppear {
            Task { @MainActor in
                NSApp.setActivationPolicy(.regular)
            }
        }
        .onDisappear {
            Task { @MainActor in
                NSApp.setActivationPolicy(.accessory)
            }
        }
        .alert("Settings Error", isPresented: Binding(
            get: { appState.settingsErrorMessage != nil },
            set: { if !$0 { appState.settingsErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.settingsErrorMessage ?? "")
        }
    }

    private var downloadFolderLabel: String {
        let path = appState.settings.downloadFolderPath
        if path.isEmpty { return "Not set" }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose default download folder"
        if panel.runModal() == .OK, let url = panel.url {
            appState.settings.downloadFolderPath = url.path
        }
    }
}

@MainActor
private func bringSettingsWindowToFront(_ window: NSWindow) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        tryResolveWindow(view: view, coordinator: context.coordinator)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            tryResolveWindow(view: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        tryResolveWindow(view: nsView, coordinator: context.coordinator)
    }

    private func tryResolveWindow(view: NSView, coordinator: Coordinator) {
        guard let window = view.window, !coordinator.didResolve else { return }
        coordinator.didResolve = true
        window.title = "Settings"
        onResolve(window)
    }

    final class Coordinator {
        var didResolve = false
    }
}
