import SwiftUI
import AppKit

struct ProfileEditorView: View {
    private enum Field: Hashable {
        case connectionName
    }

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connection Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Connection Name", text: $appState.editorConnectionName)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .connectionName)
                }

                HStack(spacing: 10) {
                    LabeledField("Server", text: $appState.editorServer)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Port")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("22", text: $appState.editorPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }

                LabeledField("Username", text: $appState.editorUsername)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Password")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("Optional", text: $appState.editorPassword)
                        .textFieldStyle(.roundedBorder)
                }

                PrivateKeyPickerView(
                    selection: $appState.editorPrivateKeyPath,
                    recentPaths: appState.recentPrivateKeyPaths,
                    onAddRecent: { appState.addRecentPrivateKeyPath($0) }
                )
        
            }

            HStack {
                if case .edit = appState.editorMode {
                    Button("Delete", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .foregroundColor(Color(.red))
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    do {
                        try appState.saveEditorProfile()
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .foregroundColor(Color(.green))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(minWidth: 300)
        .alert("Validation Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .confirmationDialog("Delete this connection?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                do {
                    try appState.deleteSelectedProfile()
                    closeProfileEditorWindow()
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .foregroundColor(Color(.red))
            Button("Cancel", role: .cancel) {}
        }
        .background(
            WindowAccessor(title: appState.editorMode.title) { window in
                guard let window else { return }
                window.level = .normal
                Task { @MainActor in bringWindowToFront(window) }
                // Menu bar apps often lose key status; reinforce so the window stays key and accepts typing.
                for delay in [0.2, 0.5] as [Double] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        Task { @MainActor in bringWindowToFront(window) }
                    }
                }
            }
        )
        .onAppear {
            Task { @MainActor in
                NSApp.setActivationPolicy(.regular)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focusedField = .connectionName
            }
        }
        .onDisappear {
            Task { @MainActor in
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

@MainActor
private func closeProfileEditorWindow() {
    let window = NSApp.windows.first { w in
        w.identifier?.rawValue.contains("profile-editor") == true
            || w.title == "Add Connection"
            || w.title == "Edit Connection"
    }
    window?.close()
}

@MainActor
private func bringWindowToFront(_ window: NSWindow) {
    // Menu bar apps use .accessory by default, which blocks keyboard input to windows.
    // Temporarily use .regular so this window can receive key events.
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
}

private struct WindowAccessor: NSViewRepresentable {
    let title: String
    let onResolve: (NSWindow?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Try immediately and again after a short delay; view.window is often nil until after layout.
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
        window.title = title
        onResolve(window)
    }

    final class Coordinator {
        var didResolve = false
    }
}

private struct LabeledField: View {
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
