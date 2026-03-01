import Foundation
#if canImport(Darwin)
import Darwin
#endif

private struct StderrStream: TextOutputStream {
    mutating func write(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}

private func logSFTP(_ message: String) {
    var stream = StderrStream()
    print(message, to: &stream)
    fflush(stderr)
    let logPath = (NSHomeDirectory() as NSString).appendingPathComponent("axessh-sftp-debug.log")
    if !FileManager.default.fileExists(atPath: logPath) {
        FileManager.default.createFile(atPath: logPath, contents: nil)
    }
    if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
        handle.seekToEndOfFile()
        handle.write(Data((message + "\n").utf8))
        try? handle.close()
    }
}

enum SFTPError: LocalizedError {
    case commandFailed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let code, let stderr):
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return msg.isEmpty ? "SFTP failed (exit \(code))" : msg
        }
    }
}

enum SFTPService {
    static func fetchFileContent(profile: SSHProfile, path: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try fetchFileContentSync(profile: profile, path: path)
                    logSFTP("[AxeSSH SFTP] Fetched file: \(path) (\(data.count) bytes)")
                    if let preview = String(data: data.prefix(200), encoding: .utf8), !preview.isEmpty {
                        let oneLine = preview.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: "")
                        logSFTP("[AxeSSH SFTP] Preview: \(oneLine)\(data.count > 200 ? "..." : "")")
                    }
                    continuation.resume(returning: data)
                } catch {
                    logSFTP("[AxeSSH SFTP] Fetch failed for \(path): \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func fetchFileContentSync(profile: SSHProfile, path: String) throws -> Data {
        let password = profile.password?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usingPassword = password.map { !$0.isEmpty } ?? false
        if usingPassword {
            return try fetchFileViaSFTPWithPassword(profile: profile, path: path)
        }
        return try fetchFileViaSFTP(profile: profile, path: path)
    }

    private static func fetchFileViaSFTPWithPassword(profile: SSHProfile, path: String) throws -> Data {
        let localPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-sftp-get").path
        defer { try? FileManager.default.removeItem(atPath: localPath) }
        let remotePath = path.contains(" ") ? "\"\(path)\"" : path
        let batchContent = "get \(remotePath) \(localPath)\nbye\n"
        let batchURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-sftp-get-batch")
        defer { try? FileManager.default.removeItem(at: batchURL) }
        try batchContent.write(to: batchURL, atomically: true, encoding: .utf8)

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-sftp-get-out")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        var sftpArgs = ["-o", "Port=\(profile.port)", "-o", "ConnectTimeout=15", "-o", "StrictHostKeyChecking=accept-new"]
        if !profile.privateKeyPath.trimmingCharacters(in: .whitespaces).isEmpty {
            let expanded = (profile.privateKeyPath as NSString).expandingTildeInPath
            sftpArgs.append(contentsOf: ["-o", "IdentityFile=\(expanded)"])
        }
        sftpArgs.append("\(profile.username)@\(profile.server)")

        let pass = profile.password!.trimmingCharacters(in: .whitespacesAndNewlines)
        let sshpassPath = SSHCommandBuilder.sshpassPath
        let scriptArgs = ["-q", outputURL.path, sshpassPath, "-p", pass, "/usr/bin/sftp"] + sftpArgs

        let (_, stderr, exitCode) = runProcess(executable: "/usr/bin/script", arguments: scriptArgs, environment: nil, stdinFile: batchURL)
        if exitCode != 0 {
            throw SFTPError.commandFailed(exitCode: exitCode, stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (try? Data(contentsOf: URL(fileURLWithPath: localPath))) ?? Data()
    }

    private static func fetchFileViaSFTP(profile: SSHProfile, path: String) throws -> Data {
        let localPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-sftp-get").path
        defer { try? FileManager.default.removeItem(atPath: localPath) }
        let remotePath = path.contains(" ") ? "\"\(path)\"" : path
        let batchContent = "get \(remotePath) \(localPath)\nbye\n"
        let batchURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-sftp-batch")
        defer { try? FileManager.default.removeItem(at: batchURL) }
        try batchContent.write(to: batchURL, atomically: true, encoding: .utf8)
        var sftpArgs = ["-o", "Port=\(profile.port)", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-b", batchURL.path]
        if !profile.privateKeyPath.trimmingCharacters(in: .whitespaces).isEmpty {
            let expanded = (profile.privateKeyPath as NSString).expandingTildeInPath
            sftpArgs.append(contentsOf: ["-o", "IdentityFile=\(expanded)"])
        }
        sftpArgs.append("\(profile.username)@\(profile.server)")
        let (_, stderr, exitCode) = runProcess(executable: "/usr/bin/sftp", arguments: sftpArgs, environment: nil, stdinFile: nil)
        if exitCode != 0 {
            throw SFTPError.commandFailed(exitCode: exitCode, stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (try? Data(contentsOf: URL(fileURLWithPath: localPath))) ?? Data()
    }

    static func uploadFiles(profile: SSHProfile, localURLs: [URL], remotePath: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try uploadFilesSync(profile: profile, localURLs: localURLs, remotePath: remotePath)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func uploadFilesSync(profile: SSHProfile, localURLs: [URL], remotePath: String) throws {
        let password = profile.password?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usingPassword = password.map { !$0.isEmpty } ?? false
        guard usingPassword else {
            try uploadFilesViaSFTP(profile: profile, localURLs: localURLs, remotePath: remotePath)
            return
        }
        try uploadFilesViaSFTPWithPassword(profile: profile, localURLs: localURLs, remotePath: remotePath)
    }

    private static func uploadFilesViaSFTPWithPassword(profile: SSHProfile, localURLs: [URL], remotePath: String) throws {
        guard !localURLs.isEmpty else { return }
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-sftp-put-out")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        var sftpArgs = ["-o", "Port=\(profile.port)", "-o", "ConnectTimeout=15", "-o", "StrictHostKeyChecking=accept-new"]
        if !profile.privateKeyPath.trimmingCharacters(in: .whitespaces).isEmpty {
            let expanded = (profile.privateKeyPath as NSString).expandingTildeInPath
            sftpArgs.append(contentsOf: ["-o", "IdentityFile=\(expanded)"])
        }
        sftpArgs.append("\(profile.username)@\(profile.server)")
        let pass = profile.password!.trimmingCharacters(in: .whitespacesAndNewlines)
        let sshpassPath = SSHCommandBuilder.sshpassPath
        let scriptArgs = ["-q", outputURL.path, sshpassPath, "-p", pass, "/usr/bin/sftp"] + sftpArgs

        var inputLines: [String] = []
        let remote = remotePath.isEmpty || remotePath == "." ? "." : remotePath
        inputLines.append("cd \(remote)")
        for url in localURLs {
            let path = url.path
            guard !path.isEmpty else { continue }
            let quoted = path.contains(" ") ? "\"\(path)\"" : path
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            inputLines.append(isDir ? "put -r \(quoted)" : "put \(quoted)")
        }
        inputLines.append("bye")

        let (_, stderr, exitCode) = runProcessWithDelayedStdin(
            executable: "/usr/bin/script", arguments: scriptArgs,
            inputLines: inputLines, delayBetweenLinesMs: 400
        )
        if exitCode != 0 {
            throw SFTPError.commandFailed(exitCode: exitCode, stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func uploadFilesViaSFTP(profile: SSHProfile, localURLs: [URL], remotePath: String) throws {
        guard !localURLs.isEmpty else { return }
        let batchURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-sftp-put-batch")
        defer { try? FileManager.default.removeItem(at: batchURL) }
        var lines: [String] = []
        let remote = remotePath.isEmpty || remotePath == "." ? "." : remotePath
        lines.append("cd \(remote)")
        for url in localURLs {
            let path = url.path
            guard !path.isEmpty else { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            lines.append(isDir ? "put -r \(path)" : "put \(path)")
        }
        lines.append("bye")
        try lines.joined(separator: "\n").write(to: batchURL, atomically: true, encoding: .utf8)
        var sftpArgs = ["-o", "Port=\(profile.port)", "-o", "ConnectTimeout=15", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-b", batchURL.path]
        if !profile.privateKeyPath.trimmingCharacters(in: .whitespaces).isEmpty {
            let expanded = (profile.privateKeyPath as NSString).expandingTildeInPath
            sftpArgs.append(contentsOf: ["-o", "IdentityFile=\(expanded)"])
        }
        sftpArgs.append("\(profile.username)@\(profile.server)")
        let (_, stderr, exitCode) = runProcess(executable: "/usr/bin/sftp", arguments: sftpArgs, environment: nil, stdinFile: nil)
        if exitCode != 0 {
            throw SFTPError.commandFailed(exitCode: exitCode, stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func deleteItems(profile: SSHProfile, paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try deleteItemsSync(profile: profile, paths: paths)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func deleteItemsSync(profile: SSHProfile, paths: [String]) throws {
        let password = profile.password?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usingPassword = password.map { !$0.isEmpty } ?? false

        let base = profile.remoteBasePath.trimmingCharacters(in: .whitespaces)
        let resolvedBase = base.isEmpty || base == "." ? "" : base
        let quotedPaths = paths.map { path -> String in
            let fullPath = resolvedBase.isEmpty ? path : "\(resolvedBase)/\(path)"
            let escaped = fullPath.replacingOccurrences(of: "'", with: "'\\''")
            return "'\(escaped)'"
        }
        let rmArg = quotedPaths.joined(separator: " ")
        let remoteCommand = resolvedBase.isEmpty ? "rm -rf \(rmArg)" : "cd '\(resolvedBase.replacingOccurrences(of: "'", with: "'\\''"))' && rm -rf \(rmArg)"

        var sshArgs = ["-o", "Port=\(profile.port)", "-o", "ConnectTimeout=15", "-o", "StrictHostKeyChecking=accept-new"]
        if !profile.privateKeyPath.trimmingCharacters(in: .whitespaces).isEmpty {
            let expanded = (profile.privateKeyPath as NSString).expandingTildeInPath
            sshArgs.append(contentsOf: ["-o", "IdentityFile=\(expanded)"])
        }
        if !usingPassword {
            sshArgs.append("-o")
            sshArgs.append("BatchMode=yes")
        }
        sshArgs.append("\(profile.username)@\(profile.server)")
        sshArgs.append(remoteCommand)

        let executable: String
        let arguments: [String]
        if usingPassword, let pass = password {
            let sshpassPath = SSHCommandBuilder.sshpassPath
            executable = sshpassPath
            arguments = ["-p", pass, "/usr/bin/ssh"] + sshArgs
        } else {
            executable = "/usr/bin/ssh"
            arguments = sshArgs
        }

        let (_, stderr, exitCode) = runProcess(executable: executable, arguments: arguments, environment: nil, stdinFile: nil)
        if exitCode != 0 {
            throw SFTPError.commandFailed(exitCode: exitCode, stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func listDirectory(profile: SSHProfile, path: String = ".") async throws -> [RemoteFileItem] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                logSFTP("[AxeSSH SFTP] listDirectory starting: \(path)")
                do {
                    let items = try listDirectorySync(profile: profile, path: path)
                    logSFTP("[AxeSSH SFTP] Listed \(path): \(items.count) items")
                    for item in items {
                        logSFTP("[AxeSSH SFTP]   \(item.isDirectory ? "d" : "-") \(item.name)")
                    }
                    continuation.resume(returning: items)
                } catch {
                    logSFTP("[AxeSSH SFTP] List failed for \(path): \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func listDirectorySync(profile: SSHProfile, path: String) throws -> [RemoteFileItem] {
        let password = profile.password?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usingPassword = password.map { !$0.isEmpty } ?? false

        if usingPassword {
            return try listViaSFTPWithPassword(profile: profile, path: path)
        }
        return try listViaSFTP(profile: profile, path: path)
    }

    /// Uses sftp with stdin (no -b) + script + sshpass. Feed commands gradually so ls output is flushed before bye.
    private static func listViaSFTPWithPassword(profile: SSHProfile, path: String) throws -> [RemoteFileItem] {
        let quotedPath = path.contains(" ") ? "\"\(path)\"" : path
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-sftp-out")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        var sftpArgs = ["-o", "Port=\(profile.port)", "-o", "ConnectTimeout=15", "-o", "StrictHostKeyChecking=accept-new"]
        if !profile.privateKeyPath.trimmingCharacters(in: .whitespaces).isEmpty {
            let expanded = (profile.privateKeyPath as NSString).expandingTildeInPath
            sftpArgs.append(contentsOf: ["-o", "IdentityFile=\(expanded)"])
        }
        sftpArgs.append("\(profile.username)@\(profile.server)")

        let pass = profile.password!.trimmingCharacters(in: .whitespacesAndNewlines)
        let sshpassPath = SSHCommandBuilder.sshpassPath
        let scriptArgs = ["-q", outputURL.path, sshpassPath, "-p", pass, "/usr/bin/sftp"] + sftpArgs

        logSFTP("[AxeSSH SFTP] Running: script sshpass sftp (stdin)")
        let (_, stderr, exitCode) = runProcessWithDelayedStdin(
            executable: "/usr/bin/script",
            arguments: scriptArgs,
            inputLines: ["ls -l \(quotedPath)", "bye"],
            delayBetweenLinesMs: 300
        )
        logSFTP("[AxeSSH SFTP] script exited with \(exitCode)")

        let output: String
        if let data = try? Data(contentsOf: outputURL) {
            output = stripControlCharacters(String(data: data, encoding: .utf8) ?? "")
        } else {
            output = ""
        }

        if exitCode != 0 {
            throw SFTPError.commandFailed(exitCode: exitCode, stderr: buildErrorMessage(stderr: stderr, scriptOutput: output))
        }
        let items = parseLsOutput(output, basePath: path)
        if items.isEmpty && !output.isEmpty {
            logSFTP("[AxeSSH SFTP] WARNING: parsed 0 items, raw output (first 1200 chars):")
            let preview = String(output.prefix(1200))
            for line in preview.components(separatedBy: "\n") {
                logSFTP("  |\(line)")
            }
        }
        return items
    }

    private static func listViaSFTP(profile: SSHProfile, path: String) throws -> [RemoteFileItem] {
        let quotedPath = path.contains(" ") ? "\"\(path)\"" : path
        let batchContent = "ls -l \(quotedPath)\nbye\n"
        let batchURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-sftp-batch")
        defer { try? FileManager.default.removeItem(at: batchURL) }
        try batchContent.write(to: batchURL, atomically: true, encoding: .utf8)

        let (executable, arguments, environment, readOutputFromFile, stdinFile) = buildSftpInvocation(profile: profile, batchPath: batchURL.path, ptyOutputPath: nil)
        let (stdout, stderr, exitCode) = runProcess(executable: executable, arguments: arguments, environment: environment, stdinFile: stdinFile)

        let output: String
        if let pathToRead = readOutputFromFile, let data = try? Data(contentsOf: URL(fileURLWithPath: pathToRead)) {
            output = stripControlCharacters(String(data: data, encoding: .utf8) ?? "")
        } else {
            output = stdout
        }

        if exitCode != 0 {
            throw SFTPError.commandFailed(exitCode: exitCode, stderr: buildErrorMessage(stderr: stderr, scriptOutput: readOutputFromFile != nil ? output : nil))
        }
        return parseLsOutput(output, basePath: path)
    }

    private static func buildErrorMessage(stderr: String, scriptOutput: String?) -> String {
        let errTrimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !errTrimmed.isEmpty { return errTrimmed }
        guard let out = scriptOutput, !out.isEmpty else { return "Connection failed." }
        let lines = out.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let errorLines = lines.suffix(6)
        return errorLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// SFTP with key-only auth (BatchMode). Password auth uses listViaSFTPWithPassword.
    private static func buildSftpInvocation(profile: SSHProfile, batchPath: String, ptyOutputPath: String?) -> (executable: String, arguments: [String], environment: [String: String]?, readOutputFromFile: String?, stdinFile: URL?) {
        var sftpArgs: [String] = [
            "-o", "Port=\(profile.port)",
            "-o", "ConnectTimeout=15",
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-b", batchPath
        ]
        let keyPath = profile.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyPath.isEmpty {
            let expanded = (keyPath as NSString).expandingTildeInPath
            sftpArgs.append(contentsOf: ["-o", "IdentityFile=\(expanded)"])
        }
        let dest = "\(profile.username)@\(profile.server)"
        sftpArgs.append(dest)
        return ("/usr/bin/sftp", sftpArgs, nil, nil, nil)
    }

    private static func runProcessWithDelayedStdin(executable: String, arguments: [String], inputLines: [String], delayBetweenLinesMs: Int) -> (stdout: String, stderr: String, exitCode: Int32) {
#if canImport(Darwin)
        signal(SIGPIPE, SIG_IGN)
#endif
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        try? process.run()

        let writeHandle = inPipe.fileHandleForWriting
        for (i, line) in inputLines.enumerated() {
            if i > 0 { usleep(useconds_t(delayBetweenLinesMs) * 1000) }
            writeHandle.write(Data((line + "\n").utf8))
        }
        try? writeHandle.close()

        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: outData, encoding: .utf8) ?? "", String(data: errData, encoding: .utf8) ?? "", process.terminationStatus)
    }

    private static func runProcess(executable: String, arguments: [String], environment: [String: String]?, stdinFile: URL?) -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let env = environment {
            process.environment = env
        }
        if let url = stdinFile, let handle = try? FileHandle(forReadingFrom: url) {
            process.standardInput = handle
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try? process.run()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        return (stdout, stderr, process.terminationStatus)
    }

    private static func stripControlCharacters(_ s: String) -> String {
        var result = s
        if let regex = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*[a-zA-Z]") {
            let ns = result as NSString
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }
        let filtered = result.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && scalar.value != 0x7F
        }
        return String(String.UnicodeScalarView(filtered))
    }

    private static func parseLsOutput(_ output: String, basePath: String) -> [RemoteFileItem] {
        let normalized = output
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let normalizedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        let pathPrefix = (normalizedBase == "." || normalizedBase.isEmpty) ? "" : (normalizedBase + "/")
        var items: [RemoteFileItem] = []

        let lines = normalized.components(separatedBy: "\n")
        let looksConcatenated = lines.contains { line in
            line.components(separatedBy: "./").count > 2 ||
            (line.count > 100 && (line.contains("drwx") || line.contains("-rw-")))
        }
        if looksConcatenated {
            items = parseConcatenatedLsOutput(normalized, pathPrefix: pathPrefix)
        }
        if items.isEmpty {
            for line in lines {
                items.append(contentsOf: parseLsLine(line.trimmingCharacters(in: .whitespacesAndNewlines), pathPrefix: pathPrefix))
            }
            if items.isEmpty, !normalized.isEmpty {
                items = parseConcatenatedLsOutput(normalized, pathPrefix: pathPrefix)
            }
        }
        return items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func parseLsLine(_ line: String, pathPrefix: String) -> [RemoteFileItem] {
        var trimmed = line
        while trimmed.hasPrefix("sftp> ") { trimmed = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        while trimmed.hasPrefix("sftp ") { trimmed = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces) }
        if trimmed.count < 11 { return [] }
        let first = trimmed.first!
        guard first == "d" || first == "-" || first == "l" || first == "b" || first == "c" || first == "s" || first == "p" else { return [] }
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 6 else { return [] }
        let isDir = parts[0].hasPrefix("d")
        let size = Int64(parts[4]) ?? 0
        let name: String
        if parts.count >= 9 { name = parts.dropFirst(8).joined(separator: " ") }
        else if parts.count >= 8 { name = parts.dropFirst(7).joined(separator: " ") }
        else { name = parts.last ?? "" }
        if name.isEmpty || name == "." || name == ".." { return [] }
        let fullPath = pathPrefix.isEmpty ? name : pathPrefix + name
        return [RemoteFileItem(name: name, path: fullPath, isDirectory: isDir, size: size, modifiedAt: nil)]
    }

    /// Handles sftp output where newlines are missing and entries are concatenated.
    private static func parseConcatenatedLsOutput(_ output: String, pathPrefix: String) -> [RemoteFileItem] {
        var items: [RemoteFileItem] = []
        let permPattern = #"([d\-l][rwx\-]{9})\s+\?\s+(\S+)\s+(\S+)\s+(\d+)\s+(\S+)\s+(\d+)\s+(\S+)\s+(?:\.\/|[\w.-]+\/)(.+?)(?=[d\-l][rwx\-]{9}\s|$)"#
        guard let regex = try? NSRegularExpression(pattern: permPattern) else { return [] }
        let ns = output as NSString
        let range = NSRange(location: 0, length: ns.length)
        regex.enumerateMatches(in: output, range: range) { match, _, _ in
            guard let m = match, m.numberOfRanges >= 9 else { return }
            let perms = ns.substring(with: m.range(at: 1))
            let size = Int64(ns.substring(with: m.range(at: 4))) ?? 0
            let name = ns.substring(with: m.range(at: 8)).trimmingCharacters(in: .whitespaces)
            if name.isEmpty || name == "." || name == ".." { return }
            let fullPath = pathPrefix.isEmpty ? name : pathPrefix + name
            items.append(RemoteFileItem(name: name, path: fullPath, isDirectory: perms.hasPrefix("d"), size: size, modifiedAt: nil))
        }
        if items.isEmpty {
            let altPattern = #"([d\-])[rwx\-]{0,9}\s+(?:\?\s+)?\S+\s+\S+\s+(\d+)\s+\S+\s+\d+\s+\S+\s+(?:\.\/|[\w.-]+\/)(.+?)(?=[d\-l][rwx\-]{9}\s|$)"#
            if let alt = try? NSRegularExpression(pattern: altPattern) {
                alt.enumerateMatches(in: output, range: range) { match, _, _ in
                    guard let m = match, m.numberOfRanges >= 4 else { return }
                    let typeChar = ns.substring(with: m.range(at: 1))
                    let size = Int64(ns.substring(with: m.range(at: 2))) ?? 0
                    let name = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty && name != "." && name != ".." {
                        let fullPath = pathPrefix.isEmpty ? name : pathPrefix + name
                        items.append(RemoteFileItem(name: name, path: fullPath, isDirectory: typeChar == "d", size: size, modifiedAt: nil))
                    }
                }
            }
        }
        if items.isEmpty {
            let simplePattern = #"([d\-l])[rwx\-]{0,9}\s+[^.]*?(?:\.\/|[\w.-]+\/)(.+?)(?=[d\-l][rwx\-]{9}\s|$)"#
            if let simple = try? NSRegularExpression(pattern: simplePattern) {
                simple.enumerateMatches(in: output, range: range) { match, _, _ in
                    guard let m = match, m.numberOfRanges >= 3 else { return }
                    let typeChar = ns.substring(with: m.range(at: 1))
                    let name = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty && name != "." && name != ".." {
                        let fullPath = pathPrefix.isEmpty ? name : pathPrefix + name
                        items.append(RemoteFileItem(name: name, path: fullPath, isDirectory: typeChar == "d", size: 0, modifiedAt: nil))
                    }
                }
            }
            if items.isEmpty {
                let fallbackPattern = #"(?:\.\/|[\w.-]+\/)(.+?)(?=[d\-l][rwx\-]{9}\s|$)"#
                if let fallback = try? NSRegularExpression(pattern: fallbackPattern) {
                    fallback.enumerateMatches(in: output, range: range) { match, _, _ in
                        guard let m = match, m.numberOfRanges >= 2 else { return }
                        let name = ns.substring(with: m.range(at: 1))
                        if !name.isEmpty && name != "." && name != ".." {
                            let fullPath = pathPrefix.isEmpty ? name : pathPrefix + name
                            items.append(RemoteFileItem(name: name, path: fullPath, isDirectory: true, size: 0, modifiedAt: nil))
                        }
                    }
                }
            }
        }
        return items
    }
}
