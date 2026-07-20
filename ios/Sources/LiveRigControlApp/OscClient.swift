import Foundation
import Network

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

    private enum Endpoint {
        case websocket(URL)
        case udp(host: NWEndpoint.Host, port: NWEndpoint.Port, label: String)
    }

    private enum OutboundMessage {
        case websocket(URLSessionWebSocketTask.Message)
        case udp(Data)
    }

    private struct QueuedMessage {
        let message: OutboundMessage
        let policy: String
        let key: String
        let expiresAt: Date?
    }

    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var udpConnection: NWConnection?
    private let udpQueue = DispatchQueue(label: "LiveRigControlApp.OscClient.UDP")
    private var reconnectTask: Task<Void, Never>?
    private var allowReconnect = false
    private var currentEndpoint: Endpoint?
    private var pendingMessages: [QueuedMessage] = []
    private let maxPendingMessages = 200

    func connect(host: String) async {
        guard let resolved = resolveEndpoint(host: host) else { return }
        if state != .disconnected, lastHost == resolved.normalizedHost {
            return
        }

        reconnectTask?.cancel()
        reconnectTask = nil
        allowReconnect = true
        lastHost = resolved.normalizedHost
        currentEndpoint = resolved.endpoint
        cleanupTransport()
        state = .connecting

        switch resolved.endpoint {
        case .websocket(let url):
            onEvent?("OSC connecting to \(url.host ?? resolved.normalizedHost):\(url.port ?? 9001)")
            let session = URLSession(configuration: .default)
            self.session = session
            webSocketTask = session.webSocketTask(with: url)
            webSocketTask?.resume()
            state = .connected
            onEvent?("OSC connected")
            receiveLoop()
            flushPending()
        case .udp(let endpointHost, let port, let label):
            onEvent?("OSC connecting to \(label)")
            let connection = NWConnection(host: endpointHost, port: port, using: .udp)
            udpConnection = connection
            connection.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                let state = newState
                Task { @MainActor [self, state, label] in
                    self.handleUdpState(state, label: label)
                }
            }
            connection.start(queue: udpQueue)
        }
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        allowReconnect = false
        pendingMessages.removeAll()
        queuedCount = 0
        currentEndpoint = nil
        cleanupTransport()
        state = .disconnected
        onEvent?("OSC disconnected")
    }

    func send(pad: Pad, state: String, queuePolicy: String? = nil) {
        guard let osc = pad.osc else { return }
        let args = osc.resolvedArgs(forState: state, value: nil)
        guard let message = makeOutboundMessage(address: osc.address, args: args, state: state) else { return }
        sendMessage(message, queueOptions: queueOptions(for: pad, policyOverride: queuePolicy))
    }

    func send(pad: Pad, value: Int) {
        guard let osc = pad.osc else { return }
        let args = osc.resolvedArgs(forState: "value", value: value)
        guard let message = makeOutboundMessage(address: osc.address, args: args, state: nil) else { return }
        sendMessage(message, queueOptions: queueOptions(for: pad))
    }

    private var lastHost: String = ""

    private func queueOptions(for pad: Pad, policyOverride: String? = nil) -> (policy: String, key: String, ttl: TimeInterval) {
        let policy = policyOverride ?? pad.queuePolicy ?? (pad.ui?.type == "slider" ? "latest" : "ttl")
        let ttl = TimeInterval(pad.queueTtlMs ?? 1000) / 1000.0
        return (policy: policy, key: pad.id, ttl: ttl)
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                Task { @MainActor in
                    self.receiveLoop()
                }
            case .failure:
                Task { @MainActor in
                    self.handleTransportFailure(message: "OSC receive failed; reconnecting")
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

    private func sendMessage(_ message: OutboundMessage, queueOptions: (policy: String, key: String, ttl: TimeInterval)? = nil) {
        switch message {
        case .websocket(let socketMessage):
            guard state == .connected, let socket = webSocketTask else {
                enqueue(message, options: queueOptions)
                return
            }

            socket.send(socketMessage) { [weak self] error in
                guard let self = self else { return }
                if error != nil {
                    Task { @MainActor in
                        self.enqueue(message, options: queueOptions)
                        self.handleTransportFailure(message: "OSC send failed; reconnecting")
                    }
                }
            }
        case .udp(let data):
            guard state == .connected, let connection = udpConnection else {
                enqueue(message, options: queueOptions)
                return
            }

            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self = self else { return }
                if let error {
                    Task { @MainActor in
                        self.enqueue(message, options: queueOptions)
                        self.handleTransportFailure(
                            message: "OSC UDP send failed: \(error.localizedDescription); reconnecting"
                        )
                    }
                }
            })
        }
    }

    private func enqueue(_ message: OutboundMessage, options: (policy: String, key: String, ttl: TimeInterval)? = nil) {
        let policy = options?.policy ?? "ttl"
        if policy == "never" || policy == "safety" {
            onEvent?("OSC offline; message dropped")
            return
        }

        let key = options?.key ?? UUID().uuidString
        if policy == "latest" {
            pendingMessages.removeAll { $0.key == key }
        }

        if pendingMessages.count >= maxPendingMessages {
            pendingMessages.removeFirst()
        }
        let expiresAt = policy == "ttl" ? Date().addingTimeInterval(options?.ttl ?? 1.0) : nil
        pendingMessages.append(QueuedMessage(message: message, policy: policy, key: key, expiresAt: expiresAt))
        queuedCount = pendingMessages.count
        onEvent?("OSC queued (\(pendingMessages.count))")
    }

    private func flushPending() {
        guard state == .connected else { return }
        let queued = pendingMessages
        pendingMessages.removeAll()
        queuedCount = 0
        var expiredCount = 0
        let now = Date()
        for queuedMessage in queued {
            if let expiresAt = queuedMessage.expiresAt, expiresAt < now {
                expiredCount += 1
                continue
            }
            sendMessage(
                queuedMessage.message,
                queueOptions: (
                    policy: queuedMessage.policy,
                    key: queuedMessage.key,
                    ttl: max(queuedMessage.expiresAt?.timeIntervalSince(now) ?? 1.0, 0.001)
                )
            )
        }
        if expiredCount > 0 {
            onEvent?("OSC expired \(expiredCount) queued message(s)")
        }
    }

    private func handleTransportFailure(message: String) {
        cleanupTransport()
        state = .disconnected
        onEvent?(message)
        scheduleReconnect(host: lastHost)
    }

    private func handleUdpState(_ newState: NWConnection.State, label: String) {
        switch newState {
        case .ready:
            state = .connected
            onEvent?("OSC connected (\(label))")
            flushPending()
        case .failed(let error):
            handleTransportFailure(message: "OSC UDP failed: \(error.localizedDescription); reconnecting")
        case .cancelled:
            if state != .disconnected {
                state = .disconnected
            }
        default:
            break
        }
    }

    private func cleanupTransport() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        udpConnection?.stateUpdateHandler = nil
        udpConnection?.cancel()
        udpConnection = nil
    }

    private func makeOutboundMessage(address: String, args: [CodableValue], state: String?) -> OutboundMessage? {
        let endpoint = currentEndpoint ?? resolveEndpoint(host: lastHost)?.endpoint
        switch endpoint {
        case .websocket, .none:
            let payload: [String: Any] = [
                "address": address,
                "args": args.map(\.jsonValue),
                "state": state ?? "value"
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
                onEvent?("OSC payload encode failed")
                return nil
            }
            return .websocket(.data(data))
        case .udp:
            return .udp(OscPacketEncoder.encode(address: address, args: args))
        }
    }

    private func resolveEndpoint(host: String) -> (endpoint: Endpoint, normalizedHost: String)? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? "localhost" : trimmed

        if value.contains("://"), let components = URLComponents(string: value),
           let scheme = components.scheme?.lowercased(), let endpointHost = components.host {
            switch scheme {
            case "ws", "wss":
                let port = components.port ?? 9001
                let normalized = "\(scheme)://\(endpointHost):\(port)"
                return (Endpoint.websocket(URL(string: normalized)!), normalized)
            case "udp", "osc":
                let portValue = components.port ?? 9000
                guard let port = NWEndpoint.Port(rawValue: UInt16(portValue)) else { return nil }
                let normalized = "udp://\(endpointHost):\(portValue)"
                return (
                    Endpoint.udp(host: .init(endpointHost), port: port, label: normalized),
                    normalized
                )
            default:
                return nil
            }
        }

        guard let url = URL(string: "ws://\(value):9001") else { return nil }
        return (.websocket(url), value)
    }
}

private enum OscPacketEncoder {
    static func encode(address: String, args: [CodableValue]) -> Data {
        var data = Data()
        appendPaddedString(address, to: &data)

        let typeTags = "," + args.map(typeTag(for:)).joined()
        appendPaddedString(typeTags, to: &data)

        for arg in args {
            appendValue(arg, to: &data)
        }

        return data
    }

    private static func typeTag(for arg: CodableValue) -> String {
        switch arg {
        case .string:
            return "s"
        case .int:
            return "i"
        case .double:
            return "f"
        case .bool(let value):
            return value ? "T" : "F"
        }
    }

    private static func appendValue(_ value: CodableValue, to data: inout Data) {
        switch value {
        case .string(let string):
            appendPaddedString(string, to: &data)
        case .int(let intValue):
            var bigEndian = Int32(clamping: intValue).bigEndian
            withUnsafeBytes(of: &bigEndian) { bytes in
                data.append(contentsOf: bytes)
            }
        case .double(let doubleValue):
            var bits = Float(doubleValue).bitPattern.bigEndian
            withUnsafeBytes(of: &bits) { bytes in
                data.append(contentsOf: bytes)
            }
        case .bool:
            break
        }
    }

    private static func appendPaddedString(_ string: String, to data: inout Data) {
        var bytes = Array(string.utf8)
        bytes.append(0)
        while bytes.count % 4 != 0 {
            bytes.append(0)
        }
        data.append(contentsOf: bytes)
    }
}

private extension OscMapping {
    func resolvedArgs(forState state: String?, value: Int?) -> [CodableValue] {
        let source: [CodableValue]
        if let state {
            switch state {
            case "on":
                source = onArgs ?? args ?? []
            case "off":
                source = offArgs ?? args ?? []
            default:
                source = args ?? []
            }
        } else {
            source = args ?? []
        }
        return source.map { $0.resolved(value: value, state: state) }
    }
}

extension CodableValue {
    fileprivate func resolved(value: Int?, state: String?) -> CodableValue {
        guard case .string(let raw) = self else { return self }
        if raw == "$value", let value {
            return .int(value)
        }
        if raw == "$value01", let value {
            return .double(Double(value) / 127.0)
        }
        if raw == "$state", let state {
            return .string(state)
        }

        var resolved = raw
        if let value {
            resolved = resolved
                .replacingOccurrences(of: "$value01", with: String(Double(value) / 127.0))
                .replacingOccurrences(of: "$value", with: String(value))
        }
        if let state {
            resolved = resolved.replacingOccurrences(of: "$state", with: state)
        }
        return .string(resolved)
    }

    var jsonValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        }
    }
}
