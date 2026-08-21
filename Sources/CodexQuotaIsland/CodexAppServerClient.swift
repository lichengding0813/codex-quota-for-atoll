import Foundation

enum CodexAppServerError: LocalizedError {
    case executableNotFound
    case processFailed(String)
    case missingResponse(String)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "没有找到 Codex。请确认 ChatGPT.app 或 Codex CLI 已安装。"
        case .processFailed(let message):
            return "Codex App Server 启动失败：\(message)"
        case .missingResponse(let method):
            return "Codex App Server 没有返回 \(method) 数据。"
        case .serverError(let message):
            return "Codex App Server 返回错误：\(message)"
        }
    }
}

struct CodexAppServerClient: Sendable {
    func fetchSnapshot() async throws -> QuotaSnapshot {
        try await Task.detached(priority: .utility) {
            try Self.fetchSnapshotSynchronously()
        }.value
    }

    private static func fetchSnapshotSynchronously() throws -> QuotaSnapshot {
        let executable = try resolveCodexExecutable()
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        process.environment = environment

        try process.run()

        let watchdog = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20, execute: watchdog)
        defer {
            watchdog.cancel()
            try? inputPipe.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
        }

        let reader = JSONLineReader(handle: outputPipe.fileHandleForReading)
        writeLine(
            "{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":{\"name\":\"codex-quota-island\",\"title\":\"Codex Quota Island\",\"version\":\"0.1.0\"},\"capabilities\":{\"experimentalApi\":true}}}",
            to: inputPipe.fileHandleForWriting
        )

        var initialized = false
        while let object = try reader.nextJSONObject() {
            try throwIfServerError(object)
            if integerID(from: object["id"]) == 1 {
                initialized = true
                break
            }
        }
        guard initialized else {
            let diagnostics = String(
                decoding: errorPipe.fileHandleForReading.availableData,
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            throw CodexAppServerError.processFailed(
                diagnostics.isEmpty ? "初始化超时" : diagnostics
            )
        }

        writeLine("{\"method\":\"initialized\"}", to: inputPipe.fileHandleForWriting)
        writeLine("{\"method\":\"account/rateLimits/read\",\"id\":2}", to: inputPipe.fileHandleForWriting)
        writeLine("{\"method\":\"account/usage/read\",\"id\":3}", to: inputPipe.fileHandleForWriting)

        var rateLimits: RateLimitsPayload?
        var usage: UsagePayload?
        let decoder = JSONDecoder()

        while rateLimits == nil || usage == nil {
            guard let object = try reader.nextJSONObject() else { break }
            try throwIfServerError(object)
            guard let id = integerID(from: object["id"]),
                  let result = object["result"]
            else { continue }

            let resultData = try JSONSerialization.data(withJSONObject: result)
            if id == 2 {
                rateLimits = try decoder.decode(RateLimitsPayload.self, from: resultData)
            } else if id == 3 {
                usage = try decoder.decode(UsagePayload.self, from: resultData)
            }
        }

        guard let rateLimits else {
            throw CodexAppServerError.missingResponse("account/rateLimits/read")
        }
        return QuotaSnapshot.make(rateLimits: rateLimits, usage: usage)
    }

    private static func writeLine(_ line: String, to handle: FileHandle) {
        handle.write(Data((line + "\n").utf8))
    }

    private static func throwIfServerError(_ object: [String: Any]) throws {
        guard let error = object["error"] as? [String: Any] else { return }
        let message = error["message"] as? String ?? String(describing: error)
        throw CodexAppServerError.serverError(message)
    }

    private static func integerID(from value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func resolveCodexExecutable() throws -> String {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(directory))
                    .appendingPathComponent("codex").path
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        throw CodexAppServerError.executableNotFound
    }
}

private final class JSONLineReader {
    private let handle: FileHandle
    private var buffer = Data()
    private let newline = Data([0x0A])

    init(handle: FileHandle) {
        self.handle = handle
    }

    func nextJSONObject() throws -> [String: Any]? {
        while true {
            if let newlineRange = buffer.range(of: newline) {
                let line = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
                guard !line.isEmpty else { continue }
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                    return object
                }
                continue
            }

            let chunk = handle.availableData
            if chunk.isEmpty {
                guard !buffer.isEmpty else { return nil }
                defer { buffer.removeAll() }
                return try? JSONSerialization.jsonObject(with: buffer) as? [String: Any]
            }
            buffer.append(chunk)
        }
    }
}
