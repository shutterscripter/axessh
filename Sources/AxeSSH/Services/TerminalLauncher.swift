import Foundation
import AppKit

enum TerminalLauncher {
    private static let iTermBundleID = "com.googlecode.iterm2"

    static func connect(profile: SSHProfile, preference: TerminalPreference) throws {
        let command = SSHCommandBuilder.buildConnectCommand(for: profile)
        let escaped = escapeForAppleScript(command)
        switch preference {
        case .auto:
            if isiTermInstalled() {
                try runIniTerm(escapedCommand: escaped)
            } else {
                try runInTerminal(escapedCommand: escaped)
            }
        case .terminal:
            try runInTerminal(escapedCommand: escaped)
        case .iTerm:
            guard isiTermInstalled() else {
                throw LaunchError("iTerm is not installed")
            }
            try runIniTerm(escapedCommand: escaped)
        }
    }

    private static func isiTermInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: iTermBundleID) != nil
    }

    private static func runIniTerm(escapedCommand: String) throws {
        let script = """
        tell application "iTerm"
            create window with default profile
            tell current session of current window
                write text "\(escapedCommand)"
            end tell
        end tell
        """
        try runAppleScript(script, failureMessage: "Failed to open iTerm session")
    }

    private static func runInTerminal(escapedCommand: String) throws {
        let script = "tell application \"Terminal\" to do script \"\(escapedCommand)\""
        try runAppleScript(script, failureMessage: "Failed to open Terminal session")
    }

    private static func runAppleScript(_ script: String, failureMessage: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw LaunchError(failureMessage)
        }
    }

    private static func escapeForAppleScript(_ command: String) -> String {
        command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct LaunchError: LocalizedError {
    private let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
