import Foundation

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
}

@MainActor
final class LogStore: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []
    @Published var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: debugKey)
        }
    }
    private let maxEntries = 200
    private let debugKey = "debug_logging_enabled"

    init() {
        if UserDefaults.standard.object(forKey: debugKey) != nil {
            isEnabled = UserDefaults.standard.bool(forKey: debugKey)
        }
    }

    func add(_ message: String) {
        guard isEnabled else { return }
        entries.append(LogEntry(timestamp: Date(), message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }
}
