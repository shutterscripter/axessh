import Foundation

enum SSHCommandBuilder {
    /// Path to sshpass: bundled binary if present, otherwise "sshpass" (expect in PATH).
    static var sshpassPath: String {
        #if SWIFT_PACKAGE
        if let path = Bundle.module.path(forResource: "sshpass", ofType: nil) {
            return path
        }
        #else
        if let path = Bundle.main.path(forResource: "sshpass", ofType: nil, inDirectory: "Resources")
            ?? Bundle.main.path(forResource: "sshpass", ofType: nil) {
            return path
        }
        #endif
        return "sshpass"
    }

    /// Builds the full command to run in Terminal. If the profile has a password, wraps with sshpass
    /// (bundled with the app or from PATH) so the user is not prompted.
    static func buildConnectCommand(for profile: SSHProfile) -> String {
        let sshCommand = buildSSHCommand(for: profile)
        if let password = profile.password, !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let path = sshpassPath
            return "\(shellEscape(path)) -p \(shellEscape(password)) \(sshCommand)"
        }
        return sshCommand
    }

    private static func buildSSHCommand(for profile: SSHProfile) -> String {
        var parts: [String] = ["ssh"]

        if !profile.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("-i")
            parts.append(shellEscape(profile.privateKeyPath))
        }

        parts.append("-p")
        parts.append("\(profile.port)")

        let destination = "\(profile.username)@\(profile.server)"
        parts.append(shellEscape(destination))

        if !profile.remoteBasePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cdCommand = "cd \(shellEscape(profile.remoteBasePath)) ; exec \\$SHELL -l"
            parts.append("-t")
            parts.append(shellEscape(cdCommand))
        }

        return parts.joined(separator: " ")
    }

    static func shellEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
