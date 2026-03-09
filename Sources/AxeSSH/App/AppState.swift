import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var profiles: [SSHProfile] = []
    @Published var selectedProfileID: UUID?
    @Published var settings: AppSettings = AppSettings() {
        didSet {
            persistSettings()
            if !isApplyingSettingsChange, oldValue.launchAtLogin != settings.launchAtLogin {
                applyLaunchAtLoginIfNeeded(enabled: settings.launchAtLogin)
            }
        }
    }
    @Published var settingsErrorMessage: String?

    @Published var editorMode: ProfileEditorMode = .create
    @Published var editorConnectionName: String = ""
    @Published var editorServer: String = ""
    @Published var editorPort: String = "22"
    @Published var editorRemoteBasePath: String = ""
    @Published var editorUsername: String = ""
    @Published var editorPassword: String = ""
    @Published var editorPrivateKeyPath: String = ""

    private let store: ProfileStore
    private let keychain = KeychainService()
    private let settingsEncoder = JSONEncoder()
    private let settingsDecoder = JSONDecoder()
    private static let recentKeysUserDefaultsKey = "recentSSHPrivateKeyPaths"
    private static let settingsUserDefaultsKey = "axessh.appSettings"
    private static let maxRecentKeys = 15

    private var runtimePasswords: [UUID: String] = [:]
    private var isApplyingSettingsChange = false

    init(store: ProfileStore = ProfileStore()) {
        self.store = store
        self.settings = Self.loadSettings(decoder: settingsDecoder)
        self.profiles = store.loadProfiles().sorted { $0.connectionName.localizedCaseInsensitiveCompare($1.connectionName) == .orderedAscending }
        self.selectedProfileID = profiles.first?.id
        migrateLegacyPasswordsIfNeeded()
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
        editorPassword = ""
        editorPrivateKeyPath = profile.privateKeyPath
    }

    func saveEditorProfile() throws {
        let trimmedName = editorConnectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedServer = editorServer.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = editorUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRemoteBasePath = editorRemoteBasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = editorPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrivateKeyPath = editorPrivateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackRemotePath = settings.defaultRemoteStartPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveRemotePath = trimmedRemoteBasePath.isEmpty ? fallbackRemotePath : trimmedRemoteBasePath
        let shouldStoreInKeychain = settings.credentialStorage == .keychain

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
                remoteBasePath: effectiveRemotePath,
                username: trimmedUsername,
                password: nil,
                privateKeyPath: trimmedPrivateKeyPath,
                status: .unknown
            )
            profiles.append(profile)
            selectedProfileID = profile.id
            try saveCredential(
                password: trimmedPassword,
                profileID: profile.id,
                storeInKeychain: shouldStoreInKeychain,
                preserveExistingIfEmpty: false
            )
        case .edit(let id):
            guard let index = profiles.firstIndex(where: { $0.id == id }) else {
                throw ValidationError("Profile not found")
            }
            profiles[index].connectionName = trimmedName
            profiles[index].server = trimmedServer
            profiles[index].port = portValue
            profiles[index].remoteBasePath = effectiveRemotePath
            profiles[index].username = trimmedUsername
            profiles[index].password = nil
            profiles[index].privateKeyPath = trimmedPrivateKeyPath
            profiles[index].updatedAt = Date()
            selectedProfileID = profiles[index].id
            try saveCredential(
                password: trimmedPassword,
                profileID: id,
                storeInKeychain: shouldStoreInKeychain,
                preserveExistingIfEmpty: shouldStoreInKeychain
            )
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
        runtimePasswords.removeValue(forKey: selectedProfileID)
        try? keychain.deletePassword(profileID: selectedProfileID)
        self.selectedProfileID = profiles.first?.id
        try persist()
    }

    func setStatus(_ status: ConnectionStatus, forProfileID id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].status = status
        if status == .disconnected {
            runtimePasswords.removeValue(forKey: id)
        }
        try? persist()
    }

    func resolveProfileCredentials(for profile: SSHProfile, reason: CredentialPromptReason) throws -> SSHProfile {
        var resolved = profile
        switch settings.credentialStorage {
        case .keychain:
            resolved.password = try keychain.loadPassword(profileID: profile.id)
        case .askEveryTime:
            if let cached = runtimePasswords[profile.id], !cached.isEmpty {
                resolved.password = cached
            } else {
                let prompted = try promptForPassword(for: profile, reason: reason)
                runtimePasswords[profile.id] = prompted
                resolved.password = prompted
            }
        }
        return resolved
    }

    func clearRuntimeCredential(for profileID: UUID) {
        runtimePasswords.removeValue(forKey: profileID)
    }

    func resetAppData() throws {
        let allProfileIDs = profiles.map(\.id)
        try? LaunchAtLoginService.setEnabled(false)
        profiles = []
        selectedProfileID = nil
        prepareForCreate()
        try store.clearProfiles()
        keychain.deletePasswords(profileIDs: allProfileIDs)
        runtimePasswords.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.recentKeysUserDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.settingsUserDefaultsKey)
        let debugLogPath = (NSHomeDirectory() as NSString).appendingPathComponent("axessh-sftp-debug.log")
        try? FileManager.default.removeItem(atPath: debugLogPath)
        settingsErrorMessage = nil
        isApplyingSettingsChange = true
        settings = AppSettings()
        isApplyingSettingsChange = false
        persistSettings()
    }

    private func persist() throws {
        try store.saveProfiles(profiles)
    }

    private func persistSettings() {
        guard let encoded = try? settingsEncoder.encode(settings) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.settingsUserDefaultsKey)
    }

    private func applyLaunchAtLoginIfNeeded(enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            settingsErrorMessage = nil
        } catch {
            settingsErrorMessage = "Launch at login could not be updated: \(error.localizedDescription)"
            isApplyingSettingsChange = true
            settings.launchAtLogin = !enabled
            isApplyingSettingsChange = false
        }
    }

    private func saveCredential(password: String, profileID: UUID, storeInKeychain: Bool, preserveExistingIfEmpty: Bool) throws {
        if storeInKeychain {
            runtimePasswords.removeValue(forKey: profileID)
            if password.isEmpty {
                if !preserveExistingIfEmpty {
                    try keychain.deletePassword(profileID: profileID)
                }
            } else {
                try keychain.savePassword(password, profileID: profileID)
            }
        } else {
            try keychain.deletePassword(profileID: profileID)
            if password.isEmpty {
                runtimePasswords.removeValue(forKey: profileID)
            } else {
                runtimePasswords[profileID] = password
            }
        }
    }

    private func migrateLegacyPasswordsIfNeeded() {
        var needsPersist = false
        for index in profiles.indices {
            guard let legacyPassword = profiles[index].password, !legacyPassword.isEmpty else { continue }
            let id = profiles[index].id
            if settings.credentialStorage == .keychain {
                try? keychain.savePassword(legacyPassword, profileID: id)
            } else {
                runtimePasswords[id] = legacyPassword
            }
            profiles[index].password = nil
            needsPersist = true
        }
        if needsPersist {
            try? persist()
        }
    }

    private static func loadSettings(decoder: JSONDecoder) -> AppSettings {
        guard
            let data = UserDefaults.standard.data(forKey: settingsUserDefaultsKey),
            let settings = try? decoder.decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        return settings
    }

    private func promptForPassword(for profile: SSHProfile, reason: CredentialPromptReason) throws -> String {
        let alert = NSAlert()
        alert.messageText = "Password Required"
        alert.informativeText = "\(reason.promptLabel)\n\(profile.username)@\(profile.server)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Password"
        alert.accessoryView = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            throw ValidationError("Password prompt was cancelled")
        }

        let password = field.stringValue.trimmingCharacters(in: .newlines)
        guard !password.isEmpty else {
            throw ValidationError("Password cannot be empty")
        }
        return password
    }
}

enum CredentialPromptReason {
    case terminalConnect
    case fileBrowser

    var promptLabel: String {
        switch self {
        case .terminalConnect:
            return "Enter password to open terminal connection."
        case .fileBrowser:
            return "Enter password to access remote files."
        }
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
