import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var profiles: [SSHProfile] = []
    @Published var selectedProfileID: UUID?

    @Published var editorMode: ProfileEditorMode = .create
    @Published var editorConnectionName: String = ""
    @Published var editorServer: String = ""
    @Published var editorPort: String = "22"
    @Published var editorRemoteBasePath: String = ""
    @Published var editorUsername: String = ""
    @Published var editorPassword: String = ""
    @Published var editorPrivateKeyPath: String = ""

    private let store: ProfileStore
    private static let recentKeysUserDefaultsKey = "recentSSHPrivateKeyPaths"
    private static let maxRecentKeys = 15

    init(store: ProfileStore = ProfileStore()) {
        self.store = store
        self.profiles = store.loadProfiles().sorted { $0.connectionName.localizedCaseInsensitiveCompare($1.connectionName) == .orderedAscending }
        self.selectedProfileID = profiles.first?.id
    }

    var recentPrivateKeyPaths: [String] {
        (UserDefaults.standard.stringArray(forKey: Self.recentKeysUserDefaultsKey) ?? [])
            .filter { FileManager.default.fileExists(atPath: ($0 as NSString).expandingTildeInPath) }
    }

    func addRecentPrivateKeyPath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let expanded = (trimmed as NSString).expandingTildeInPath
        var recent = (UserDefaults.standard.stringArray(forKey: Self.recentKeysUserDefaultsKey) ?? [])
            .map { ($0 as NSString).expandingTildeInPath }
        recent.removeAll { $0 == expanded }
        recent.insert(expanded, at: 0)
        recent = Array(recent.prefix(Self.maxRecentKeys))
        UserDefaults.standard.set(recent.map { ($0 as NSString).abbreviatingWithTildeInPath }, forKey: Self.recentKeysUserDefaultsKey)
        objectWillChange.send()
    }

    var selectedProfile: SSHProfile? {
        guard let id = selectedProfileID else { return nil }
        return profiles.first(where: { $0.id == id })
    }

    func prepareForCreate() {
        editorMode = .create
        editorConnectionName = ""
        editorServer = ""
        editorPort = "22"
        editorRemoteBasePath = ""
        editorUsername = ""
        editorPassword = ""
        editorPrivateKeyPath = ""
    }

    func prepareForEdit(_ profile: SSHProfile) {
        editorMode = .edit(profile.id)
        editorConnectionName = profile.connectionName
        editorServer = profile.server
        editorPort = String(profile.port)
        editorRemoteBasePath = profile.remoteBasePath
        editorUsername = profile.username
        editorPassword = profile.password ?? ""
        editorPrivateKeyPath = profile.privateKeyPath
    }

    func saveEditorProfile() throws {
        let trimmedName = editorConnectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedServer = editorServer.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = editorUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRemoteBasePath = editorRemoteBasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = editorPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrivateKeyPath = editorPrivateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            throw ValidationError("Connection name is required")
        }
        guard !trimmedServer.isEmpty else {
            throw ValidationError("Server is required")
        }
        guard !trimmedUsername.isEmpty else {
            throw ValidationError("Username is required")
        }
        guard let portValue = Int(editorPort), (1...65535).contains(portValue) else {
            throw ValidationError("Port must be between 1 and 65535")
        }

        switch editorMode {
        case .create:
            let profile = SSHProfile(
                connectionName: trimmedName,
                server: trimmedServer,
                port: portValue,
                remoteBasePath: trimmedRemoteBasePath,
                username: trimmedUsername,
                password: trimmedPassword.isEmpty ? nil : trimmedPassword,
                privateKeyPath: trimmedPrivateKeyPath,
                status: .unknown
            )
            profiles.append(profile)
            selectedProfileID = profile.id
        case .edit(let id):
            guard let index = profiles.firstIndex(where: { $0.id == id }) else {
                throw ValidationError("Profile not found")
            }
            profiles[index].connectionName = trimmedName
            profiles[index].server = trimmedServer
            profiles[index].port = portValue
            profiles[index].remoteBasePath = trimmedRemoteBasePath
            profiles[index].username = trimmedUsername
            profiles[index].password = trimmedPassword.isEmpty ? nil : trimmedPassword
            profiles[index].privateKeyPath = trimmedPrivateKeyPath
            profiles[index].updatedAt = Date()
            selectedProfileID = profiles[index].id
        }

        profiles.sort { $0.connectionName.localizedCaseInsensitiveCompare($1.connectionName) == .orderedAscending }
        if !trimmedPrivateKeyPath.isEmpty {
            addRecentPrivateKeyPath(trimmedPrivateKeyPath)
        }
        try persist()
    }

    func deleteSelectedProfile() throws {
        guard let selectedProfileID else { return }
        profiles.removeAll(where: { $0.id == selectedProfileID })
        self.selectedProfileID = profiles.first?.id
        try persist()
    }

    func setStatus(_ status: ConnectionStatus, forProfileID id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].status = status
        try? persist()
    }

    private func persist() throws {
        try store.saveProfiles(profiles)
    }
}

enum ProfileEditorMode: Equatable {
    case create
    case edit(UUID)

    var title: String {
        switch self {
        case .create:
            return "Add Connection"
        case .edit:
            return "Edit Connection"
        }
    }
}

struct ValidationError: LocalizedError {
    private let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
