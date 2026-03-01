import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FileBrowserView: View {
    @EnvironmentObject private var appState: AppState

    @State private var pathComponents: [String] = []
    @State private var items: [RemoteFileItem] = []
    @State private var isLoading = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var showOverwriteConfirmation = false
    @State private var pendingUploadURLs: [URL] = []
    @State private var conflictingNames: [String] = []
    @State private var selectedItems: Set<RemoteFileItem> = []
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var isDropTarget = false

    private var currentPath: String {
        if pathComponents.isEmpty {
            let base = profile?.remoteBasePath.trimmingCharacters(in: .whitespaces) ?? ""
            return base.isEmpty ? "." : base
        }
        return pathComponents.joined(separator: "/")
    }

    private var profile: SSHProfile? {
        appState.selectedProfile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            pathBar
            Divider()
            content
        }
        .frame(minWidth: 600, minHeight: 420)
        .background(
            FileBrowserWindowAccessor { window in
                guard let window else { return }
                window.level = .normal
                Task { @MainActor in bringFileBrowserWindowToFront(window) }
                for delay in [0.2, 0.5] as [Double] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        Task { @MainActor in bringFileBrowserWindowToFront(window) }
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
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showOverwriteConfirmation) {
            overwriteConfirmationSheet
        }
        .confirmationDialog("Delete Items?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await performDelete() }
            }
            Button("Cancel", role: .cancel) {
                showDeleteConfirmation = false
            }
        } message: {
            let count = selectedItems.count
            Text("Delete \(count) item\(count == 1 ? "" : "s")? This cannot be undone.")
        }
        .task(id: currentPath) {
            guard profile != nil else { return }
            selectedItems = []
            await loadDirectory()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            
            if isUploading {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Uploading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var pathBar: some View {
        HStack(spacing: 12) {
            Button {
                pathComponents.removeAll()
                selectedItems = []
            } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(pathComponents.isEmpty)

            ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                Text("/")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button(component) {
                    pathComponents = Array(pathComponents.prefix(index + 1))
                    selectedItems = []
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            Spacer(minLength: 0)
            if profile != nil {
                Button {
                    Task { await loadDirectory() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .help("Refresh")
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .disabled(selectedItems.isEmpty || isDeleting)
                .help("Delete selected")
                Button {
                    openUploadPanel()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .disabled(isUploading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if profile == nil {
            emptyState
        } else if isLoading {
            loadingState
        } else {
            listContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { handleDrop(providers: $0) }
                .overlay {
                    if isDropTarget {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(0.12))
                            .overlay {
                                VStack(spacing: 10) {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 40))
                                    Text("Drop to upload")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .padding(12)
                    }
                }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No connection selected")
                .font(.headline)
            Text("Select a connection from the menu to browse its files.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listContent: some View {
        List(selection: $selectedItems) {
            ForEach(items) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                        .foregroundStyle(item.isDirectory ? Color(nsColor: .systemYellow) : Color(nsColor: .secondaryLabelColor))
                        .frame(width: 24, alignment: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(.body, design: .default))
                            .lineLimit(1)
                        if let size = item.size, !item.isDirectory {
                            Text(byteCountFormatter.string(fromByteCount: size))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .tag(item)
                .highPriorityGesture(
                    TapGesture(count: 2).onEnded { _ in
                        if item.isDirectory {
                            pathComponents.append(item.name)
                            selectedItems = []
                        }
                    }
                )
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            handleDrop(providers: providers)
        }
    }

    private var byteCountFormatter: ByteCountFormatter {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }

    @ViewBuilder
    private var overwriteConfirmationSheet: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Overwrite Existing Files?")
                    .font(.headline)
                Text("The following already exist in this folder. Overwriting will replace them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(conflictingNames, id: \.self) { name in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(name)
                                .font(.system(.body, design: .default))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 200)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    pendingUploadURLs = []
                    conflictingNames = []
                    showOverwriteConfirmation = false
                }
                .keyboardShortcut(.cancelAction)
                Button("Overwrite") {
                    let urls = pendingUploadURLs
                    pendingUploadURLs = []
                    conflictingNames = []
                    showOverwriteConfirmation = false
                    Task { await performUpload(urls) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(20)
        }
        .frame(width: 420)
    }

    private func performDelete() async {
        guard let profile = profile, !selectedItems.isEmpty else { return }
        let toDelete = selectedItems
        selectedItems = []
        showDeleteConfirmation = false
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await SFTPService.deleteItems(profile: profile, paths: toDelete.map(\.path))
            await loadDirectory()
        } catch {
            errorMessage = error.localizedDescription
            selectedItems = toDelete
        }
    }

    private func loadDirectory() async {
        guard let profile = profile else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await SFTPService.listDirectory(profile: profile, path: currentPath)
        } catch {
            errorMessage = error.localizedDescription
            items = []
        }
    }

    private func openUploadPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.prompt = "Upload"
        panel.message = "Select files or folders to upload"
        panel.begin { response in
            guard response == .OK else { return }
            let urls = panel.urls
            guard !urls.isEmpty else { return }
            Task { await uploadFiles(urls) }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard profile != nil, !isUploading else { return false }
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        let urlsLock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in fileProviders {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urlsLock.lock()
                    urls.append(url)
                    urlsLock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            urlsLock.lock()
            let toUpload = urls
            urlsLock.unlock()
            guard !toUpload.isEmpty else { return }
            Task { await uploadFiles(toUpload) }
        }
        return true
    }

    private func uploadFiles(_ urls: [URL]) async {
        guard let profile = profile else { return }
        let names = urls.map { $0.lastPathComponent }
        let existingNames = Set(items.map { $0.name })
        let conflicts = names.filter { existingNames.contains($0) }
        if !conflicts.isEmpty {
            conflictingNames = conflicts
            pendingUploadURLs = urls
            showOverwriteConfirmation = true
            return
        }
        await performUpload(urls)
    }

    private func performUpload(_ urls: [URL]) async {
        guard let profile = profile else { return }
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        do {
            try await SFTPService.uploadFiles(profile: profile, localURLs: urls, remotePath: currentPath)
            await loadDirectory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}

@MainActor
private func bringFileBrowserWindowToFront(_ window: NSWindow) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
}

private struct FileBrowserWindowAccessor: NSViewRepresentable {
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
        window.title = "File Browser"
        onResolve(window)
    }

    final class Coordinator {
        var didResolve = false
    }
}
