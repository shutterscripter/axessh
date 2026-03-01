import Foundation

struct SSHProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var connectionName: String
    var server: String
    var port: Int
    var remoteBasePath: String
    var username: String
    var password: String?
    var privateKeyPath: String
    var status: ConnectionStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        connectionName: String,
        server: String,
        port: Int = 22,
        remoteBasePath: String = "",
        username: String,
        password: String? = nil,
        privateKeyPath: String = "",
        status: ConnectionStatus = .unknown,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.connectionName = connectionName
        self.server = server
        self.port = port
        self.remoteBasePath = remoteBasePath
        self.username = username
        self.password = password
        self.privateKeyPath = privateKeyPath
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum ConnectionStatus: String, Codable, CaseIterable {
    case unknown
    case connected
    case disconnected

    var label: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        }
    }
}
