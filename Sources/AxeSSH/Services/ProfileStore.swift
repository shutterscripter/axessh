import Foundation

final class ProfileStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("AxeSSH", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        self.fileURL = directory.appendingPathComponent("profiles.json")

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadProfiles() -> [SSHProfile] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        guard let profiles = try? decoder.decode([SSHProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    func saveProfiles(_ profiles: [SSHProfile]) throws {
        let data = try encoder.encode(profiles)
        try data.write(to: fileURL, options: .atomic)
    }
}
