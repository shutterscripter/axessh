import Foundation

enum TerminalPreference: String, Codable, CaseIterable, Identifiable {
    case auto
    case terminal
    case iTerm

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .terminal: return "Terminal"
        case .iTerm: return "iTerm"
        }
    }
}

enum CredentialStoragePreference: String, Codable, CaseIterable, Identifiable {
    case keychain
    case askEveryTime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .keychain: return "Keychain"
        case .askEveryTime: return "Ask Every Time"
        }
    }
}

enum UploadConflictPolicy: String, Codable, CaseIterable, Identifiable {
    case ask
    case overwrite
    case skip

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }
}

struct AppSettings: Codable, Equatable {
    var defaultTerminal: TerminalPreference = .auto
    var credentialStorage: CredentialStoragePreference = .keychain
    var defaultRemoteStartPath: String = ""
    var showHiddenFiles: Bool = false
    var uploadConflictPolicy: UploadConflictPolicy = .ask
    var downloadFolderPath: String = AppSettings.defaultDownloadFolderPath()
    var launchAtLogin: Bool = false

    private static func defaultDownloadFolderPath() -> String {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let path = downloadsURL?.path ?? (NSHomeDirectory() as NSString).appendingPathComponent("Downloads")
        return (path as NSString).abbreviatingWithTildeInPath
    }
}
