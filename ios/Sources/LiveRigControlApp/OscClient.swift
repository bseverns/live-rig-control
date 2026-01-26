import Foundation

@MainActor
final class OscClient: ObservableObject {
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
    }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var queuedCount: Int = 0
    var onEvent: ((String) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var reconnectTask: Task<Void, Never>?
    private var allowReconnect = false
    private var pendingMessages: [URLSessionWebSocketTask.Message] = []
    private let maxPendingMessages = 200

    func connect(host: String) async {
        guard let url = makeOscUrl(host: host) else { return }
        if webSocketTask != nil { return }

        allowReconnect = true
        state = .connecting
        onEvent?("OSC connecting to \(url.host ?? host):\(url.port ?? 9001)")
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        state = .connected
        onEvent?("OSC connected")
        receiveLoop()
        flushPending()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        allowReconnect = false
        pendingMessages.removeAll()
        queuedCount = 0
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        state = .disconnected
        onEvent?("OSC disconnected")
    }

    func send(pad: Pad, state: String) {
        guard let osc = pad.osc else { return }

        let payload: [String: Any] = [
            "address": osc.address,
            "args": osc.args?.map { $0.jsonValue } ?? [],
            "state": state
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            onEvent?("OSC payload encode failed")
            return
        }

        let message = URLSessionWebSocketTask.Message.data(data)
        sendMessage(message)
    }

    private var lastHost: String = ""

    private func makeOscUrl(host: String) -> URL? {
        let resolvedHost = host.isEmpty ? "localhost" : host
        lastHost = resolvedHost
        return URL(string: "ws://\(resolvedHost):9001")
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.receiveLoop()
            case .failure:
                DispatchQueue.main.async {
                    self.state = .disconnected
                    self.onEvent?("OSC receive failed; reconnecting")
                    self.scheduleReconnect(host: self.lastHost)
                }
            }
        }
    }

    private func scheduleReconnect(host: String) {
        guard allowReconnect else { return }
        if reconnectTask != nil { return }
        reconnectTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self.connect(host: host)
                if self.state == .connected { break }
            }
            self.reconnectTask = nil
        }
    }

    private func sendMessage(_ message: URLSessionWebSocketTask.Message) {
        guard state == .connected, let socket = webSocketTask else {
            enqueue(message)
            return
        }

        socket.send(message) { [weak self] error in
            guard let self = self else { return }
            if error != nil {
                DispatchQueue.main.async {
                    self.state = .disconnected
                    self.onEvent?("OSC send failed; reconnecting")
                    self.scheduleReconnect(host: self.lastHost)
                }
            }
        }
    }

    private func enqueue(_ message: URLSessionWebSocketTask.Message) {
        if pendingMessages.count >= maxPendingMessages {
            pendingMessages.removeFirst()
        }
        pendingMessages.append(message)
        queuedCount = pendingMessages.count
        onEvent?("OSC queued (\(pendingMessages.count))")
    }

    private func flushPending() {
        guard state == .connected, let _ = webSocketTask else { return }
        let queued = pendingMessages
        pendingMessages.removeAll()
        queuedCount = 0
        for message in queued {
            sendMessage(message)
        }
    }
}

extension CodableValue {
    var jsonValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        }
    }
}
