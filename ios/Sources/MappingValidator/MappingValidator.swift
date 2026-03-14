import Foundation

public struct Mapping: Codable {
    public let profiles: [String: Profile]
}

public struct Profile: Codable {
    public let label: String?
    public let gridSize: [Int]?
    public let pads: [Pad]
}

public struct Pad: Codable {
    public let id: String
    public let label: String?
    public let row: Int?
    public let col: Int?
    public let toggle: Bool?
    public let mode: String?
    public let midi: MidiMapping?
    public let osc: OscMapping?
    public let ui: UiMapping?
    public let group: GroupMapping?
}

public struct GroupMapping: Codable {
    public let id: String
    public let mode: String?
    public let exclusive: Bool?

    public init(from decoder: Decoder) throws {
        let singleValue = try decoder.singleValueContainer()
        if let id = try? singleValue.decode(String.self) {
            self.id = id
            self.mode = "exclusive"
            self.exclusive = true
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        exclusive = try container.decodeIfPresent(Bool.self, forKey: .exclusive)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case mode
        case exclusive
    }
}

public struct MidiMapping: Codable {
    public let type: String?
    public let channel: Int?
    public let note: Int?
    public let cc: Int?
    public let onVelocity: Int?
    public let offVelocity: Int?
    public let onValue: Int?
    public let offValue: Int?
    public let program: Int?
    public let bankMsb: Int?
    public let bankLsb: Int?
    public let programBankMode: String?
    public let realtime: String?
}

public struct OscMapping: Codable {
    public let address: String?
}

public struct UiMapping: Codable {
    public let type: String?
    public let role: String?
    public let min: Int?
    public let max: Int?
    public let step: Int?
    public let initial: Int?
    public let showValue: Bool?
    public let target: String?
    public let bank: Int?
}

public struct ValidationResult {
    public var errors: [String]
    public var warnings: [String]

    public init(errors: [String] = [], warnings: [String] = []) {
        self.errors = errors
        self.warnings = warnings
    }
}

public struct MappingValidator {
    public init() {}

    public func validate(_ mapping: Mapping) -> ValidationResult {
        var result = ValidationResult()
        var globalPadIds: Set<String> = []

        for (profileId, profile) in mapping.profiles {
            let grid = profile.gridSize
            if grid == nil {
                result.warnings.append("[\(profileId)] Missing gridSize; defaulting to 8x8.")
            }
            if let grid, grid.count != 2 {
                result.errors.append("[\(profileId)] gridSize must be [cols, rows].")
            }
            let cols = grid?.first ?? 8
            let rows = grid?.last ?? 8
            if cols <= 0 || rows <= 0 {
                result.errors.append("[\(profileId)] gridSize must be positive.")
            }

            var occupied: Set<String> = []

            for (index, pad) in profile.pads.enumerated() {
                if pad.id.isEmpty {
                    result.errors.append("[\(profileId)] pad missing id at index \(index).")
                    continue
                }
                if globalPadIds.contains(pad.id) {
                    result.warnings.append("[\(profileId)] duplicate pad id across profiles: \(pad.id)")
                } else {
                    globalPadIds.insert(pad.id)
                }

                let row = pad.row ?? (index / max(cols, 1))
                let col = pad.col ?? (index % max(cols, 1))

                if row < 0 || row >= rows {
                    result.errors.append("[\(profileId)] pad \(pad.id) row \(row) out of bounds (0-\(rows - 1)).")
                }
                if col < 0 || col >= cols {
                    result.errors.append("[\(profileId)] pad \(pad.id) col \(col) out of bounds (0-\(cols - 1)).")
                }
                let key = "\(row),\(col)"
                if occupied.contains(key) {
                    result.errors.append("[\(profileId)] pad \(pad.id) collides at \(key).")
                } else {
                    occupied.insert(key)
                }

                if pad.midi == nil && pad.osc == nil && pad.ui == nil {
                    result.warnings.append("[\(profileId)] pad \(pad.id) has no midi/osc/ui mapping.")
                }

                if let group = pad.group, group.id.isEmpty {
                    result.errors.append("[\(profileId)] pad \(pad.id) group.id missing.")
                }

                if let ui = pad.ui {
                    if ui.type == "slider" {
                        let minValue = ui.min ?? 0
                        let maxValue = ui.max ?? 127
                        if minValue > maxValue {
                            result.errors.append("[\(profileId)] pad \(pad.id) ui.min > ui.max.")
                        }
                        if let step = ui.step, step <= 0 {
                            result.errors.append("[\(profileId)] pad \(pad.id) ui.step must be >= 1.")
                        }
                        if let initial = ui.initial {
                            let clamped = clamp(initial, min: minValue, max: maxValue)
                            if clamped != initial {
                                result.warnings.append("[\(profileId)] pad \(pad.id) ui.initial \(initial) out of range \(minValue)-\(maxValue).")
                            }
                        }
                    }
                    if ui.role == "patternBank", ui.bank == nil {
                        result.errors.append("[\(profileId)] pad \(pad.id) ui.role=patternBank missing ui.bank.")
                    }
                    if ui.role == "velocityOverride", ui.target == nil {
                        result.errors.append("[\(profileId)] pad \(pad.id) ui.role=velocityOverride missing ui.target.")
                    }
                }

                if let midi = pad.midi {
                    let prefix = "[\(profileId)] pad \(pad.id) "
                    if midi.type == nil {
                        result.errors.append(prefix + "midi.type missing.")
                    }
                    if midi.type != "realtime" {
                        if midi.channel == nil {
                            result.errors.append(prefix + "midi.channel missing.")
                        } else {
                            validateRange("midi.channel", midi.channel, min: 1, max: 16, result: &result, prefix: prefix)
                        }
                    }

                    switch midi.type {
                    case "note":
                        validateRange("midi.note", midi.note, min: 0, max: 127, result: &result, prefix: prefix)
                        validateRange("midi.onVelocity", midi.onVelocity, min: 0, max: 127, result: &result, prefix: prefix)
                        validateRange("midi.offVelocity", midi.offVelocity, min: 0, max: 127, result: &result, prefix: prefix)
                    case "cc":
                        validateRange("midi.cc", midi.cc, min: 0, max: 127, result: &result, prefix: prefix)
                        validateRange("midi.onValue", midi.onValue, min: 0, max: 127, result: &result, prefix: prefix)
                        validateRange("midi.offValue", midi.offValue, min: 0, max: 127, result: &result, prefix: prefix)
                    case "program":
                        validateRange("midi.program", midi.program, min: 0, max: 127, result: &result, prefix: prefix)
                        validateRange("midi.bankMsb", midi.bankMsb, min: 0, max: 127, result: &result, prefix: prefix)
                        validateRange("midi.bankLsb", midi.bankLsb, min: 0, max: 127, result: &result, prefix: prefix)
                    case "realtime":
                        if let realtime = midi.realtime {
                            let allowed = ["start", "continue", "stop"]
                            if !allowed.contains(realtime) {
                                result.errors.append(prefix + "midi.realtime invalid (\(realtime)).")
                            }
                        } else {
                            result.errors.append(prefix + "midi.realtime missing.")
                        }
                    case .none:
                        break
                    case .some:
                        result.warnings.append(prefix + "midi.type unrecognized.")
                    }
                }
            }
        }

        return result
    }
}

func clamp(_ value: Int, min: Int, max: Int) -> Int {
    Swift.min(max, Swift.max(min, value))
}

func validateRange(_ label: String, _ value: Int?, min: Int, max: Int, result: inout ValidationResult, prefix: String) {
    guard let value else { return }
    if value < min || value > max {
        result.errors.append("\(prefix)\(label) out of range (\(value)); expected \(min)-\(max)")
    }
}
