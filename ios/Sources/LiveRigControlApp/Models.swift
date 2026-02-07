import Foundation

struct Mapping: Codable {
    let profiles: [String: Profile]

    func normalizedProfiles() -> [Profile] {
        profiles.map { key, value in
            Profile(id: key, label: value.label, gridSize: value.gridSize, pads: value.pads)
        }
        .sorted { $0.id < $1.id }
    }
}

struct Profile: Codable, Identifiable {
    let id: String
    let label: String?
    let gridSize: [Int]?
    let pads: [Pad]

    init(id: String, label: String?, gridSize: [Int]?, pads: [Pad]) {
        self.id = id
        self.label = label
        self.gridSize = gridSize
        self.pads = pads
    }

    enum CodingKeys: String, CodingKey {
        case label, gridSize, pads
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        gridSize = try container.decodeIfPresent([Int].self, forKey: .gridSize)
        pads = try container.decode([Pad].self, forKey: .pads)
        id = ""
    }
}

struct Pad: Codable, Identifiable {
    let id: String
    let label: String?
    let row: Int?
    let col: Int?
    let toggle: Bool?
    let midi: MidiMapping?
    let osc: OscMapping?
    let notes: String?
    let ui: UiMapping?

    var isToggle: Bool {
        toggle ?? false
    }
}

struct MidiMapping: Codable {
    let type: String
    let channel: Int
    let note: Int?
    let cc: Int?
    let onVelocity: Int?
    let offVelocity: Int?
    let onValue: Int?
    let offValue: Int?
    let program: Int?
    let bankMsb: Int?
    let bankLsb: Int?
    let programBankMode: String?
    let realtime: String?
}

struct OscMapping: Codable {
    let address: String
    let args: [CodableValue]?
}

struct UiMapping: Codable {
    let type: String?
    let role: String?
    let min: Int?
    let max: Int?
    let step: Int?
    let initial: Int?
    let showValue: Bool?
    let target: String?
    let bank: Int?
}

enum CodableValue: Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        throw DecodingError.typeMismatch(
            CodableValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported OSC arg type")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        }
    }
}
