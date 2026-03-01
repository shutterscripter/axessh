import Foundation

struct RemoteFileItem: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64?
    let modifiedAt: Date?

    init(name: String, path: String, isDirectory: Bool, size: Int64? = nil, modifiedAt: Date? = nil) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedAt = modifiedAt
        self.id = path
    }
}
