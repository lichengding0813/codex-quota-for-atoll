import Foundation
import Network

/// Serves one token-protected, loopback-only refresh action for Atoll's web card.
final class CodexMonitorActionServer {
    private let token = UUID().uuidString
    private let queue = DispatchQueue(label: "com.dinglicheng.CodexQuotaIsland.monitor-action")
    private var listener: NWListener?
    private var readyContinuation: CheckedContinuation<UInt16?, Never>?

    var onRefreshMonitoring: (@MainActor () async -> Void)?

    deinit {
        stop()
    }

    func start() async -> UInt16? {
        if let port = listener?.port?.rawValue {
            return port
        }
        if listener != nil {
            return await withCheckedContinuation { readyContinuation = $0 }
        }

        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            let listener = try NWListener(using: parameters, on: .any)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] in self?.handle($0) }
            listener.stateUpdateHandler = { [weak self] in self?.handleStateUpdate($0) }

            return await withCheckedContinuation { continuation in
                readyContinuation = continuation
                listener.start(queue: queue)
            }
        } catch {
            listener = nil
            return nil
        }
    }

    func endpointURL(port: UInt16) -> String {
        "http://127.0.0.1:\(port)/refresh-monitoring?token=\(token)"
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        readyContinuation?.resume(returning: nil)
        readyContinuation = nil
    }

    private func handleStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            readyContinuation?.resume(returning: listener?.port?.rawValue)
            readyContinuation = nil
        case .failed:
            readyContinuation?.resume(returning: nil)
            readyContinuation = nil
            listener?.cancel()
            listener = nil
        default:
            break
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }

            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let validPrefix = "GET /refresh-monitoring?token=\(self.token) "
            let isValid = request.hasPrefix(validPrefix)
            if isValid {
                Task { @MainActor [weak self] in
                    guard let self else {
                        connection.cancel()
                        return
                    }
                    await self.onRefreshMonitoring?()
                    self.sendResponse("204 No Content", over: connection)
                }
                return
            }

            self.sendResponse("403 Forbidden", over: connection)
        }
    }

    private func sendResponse(_ status: String, over connection: NWConnection) {
        let response = """
        HTTP/1.1 \(status)\r
        Access-Control-Allow-Origin: *\r
        Cache-Control: no-store\r
        Content-Length: 0\r
        Connection: close\r
        \r

        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
