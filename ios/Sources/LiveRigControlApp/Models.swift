import Foundation

struct Mapping: Codable {
    let profiles: [String: Profile]

    func normalizedProfiles() -> [Profile] {
        profiles.map { key, value in
            Profile(
                id: key,
                label: value.label,
                section: value.section,
                order: value.order,
                layout: value.layout,
                gridSize: value.gridSize,
                pads: value.pads
            )
        }
        .sorted {
            if $0.performerSection.rank != $1.performerSection.rank {
                return $0.performerSection.rank < $1.performerSection.rank
            }
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return ($0.label ?? $0.id) < ($1.label ?? $1.id)
        }
    }
}

enum PerformerSection: String, CaseIterable, Identifiable {
    case show
    case sound
    case video
    case setup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .show:
            return "Show"
        case .sound:
            return "Sound"
        case .video:
            return "Video"
        case .setup:
            return "Setup"
        }
    }

    var rank: Int {
        switch self {
        case .show:
            return 0
        case .sound:
            return 1
        case .video:
            return 2
        case .setup:
            return 3
        }
    }
}

struct Profile: Codable, Identifiable {
    let id: String
    let label: String?
    let section: String?
    let order: Int?
    let layout: LayoutMapping?
    let gridSize: [Int]?
    let pads: [Pad]

    init(id: String, label: String?, section: String?, order: Int?, layout: LayoutMapping?, gridSize: [Int]?, pads: [Pad]) {
        self.id = id
        self.label = label
        self.section = section
        self.order = order
        self.layout = layout
        self.gridSize = gridSize
        self.pads = pads
    }

    enum CodingKeys: String, CodingKey {
        case label, section, order, layout, gridSize, pads
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        section = try container.decodeIfPresent(String.self, forKey: .section)
        order = try container.decodeIfPresent(Int.self, forKey: .order)
        layout = try container.decodeIfPresent(LayoutMapping.self, forKey: .layout)
        gridSize = try container.decodeIfPresent([Int].self, forKey: .gridSize)
        pads = try container.decode([Pad].self, forKey: .pads)
        id = ""
    }

    var performerSection: PerformerSection {
        PerformerSection(rawValue: section?.lowercased() ?? "") ?? .show
    }

    var sortOrder: Int {
        order ?? 999
    }
}

struct Pad: Codable, Identifiable {
    let id: String
    let label: String?
    let row: Int?
    let col: Int?
    let toggle: Bool?
    let mode: String?
    let midi: MidiMapping?
    let osc: OscMapping?
    let notes: String?
    let ui: UiMapping?
    let group: GroupMapping?
    let risk: String?
    let queuePolicy: String?
    let queueTtlMs: Int?

    var isToggle: Bool {
        if ui?.type == "slider" {
            return false
        }
        if ui?.role == "patternBank" {
            return true
        }
        if let toggle {
            return toggle
        }
        return mode == "toggle"
    }
}

struct LayoutMapping: Codable {
    let kind: String
    let minCardWidth: Int?
    let riskDisplay: Bool?
}

struct GroupMapping: Codable {
    let id: String
    let mode: String?
    let exclusive: Bool?

    init(id: String, mode: String? = nil, exclusive: Bool? = nil) {
        self.id = id
        self.mode = mode
        self.exclusive = exclusive
    }

    init(from decoder: Decoder) throws {
        let singleValue = try decoder.singleValueContainer()
        if let id = try? singleValue.decode(String.self) {
            self.id = id
            self.mode = "exclusive"
            self.exclusive = true
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.mode = try container.decodeIfPresent(String.self, forKey: .mode)
        self.exclusive = try container.decodeIfPresent(Bool.self, forKey: .exclusive)
    }

    var isExclusive: Bool {
        mode == "exclusive" || exclusive == true
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case mode
        case exclusive
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
    let onArgs: [CodableValue]?
    let offArgs: [CodableValue]?
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
