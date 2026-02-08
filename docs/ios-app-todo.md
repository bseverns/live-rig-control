# iPadOS Swift App TODO (Core MIDI + OSC)

## Goals
- Mirror the web app UX on iPad (profile bar + pad grid).
- Replace WebMIDI with Core MIDI.
- Keep OSC bridge behavior and payloads consistent.

## Status (2026-02-07)
- DONE: SwiftUI app in `ios/` with Core MIDI send (note/cc/program/realtime) + OSC WebSocket client.
- DONE: Profile bar + grid + toggle/momentary behavior + sliders (including velocity + per-pad overrides).
- DONE: Mappings bundled + loaded at launch (`Resources/mappings.json`).
- DONE: QR scan + OSC host persistence + connection status UI.
- DONE: iPad-only Xcode app target at `ios/LiveRigControlApp.xcodeproj` (uses `App/Info.plist` + iPad-only device family).
- DONE: Persist selected profile, selected MIDI output, and OSC enabled state.
- DONE: Add a small known-good `mappings.json` fixture for tests (`ios/Tests/fixtures/mappings.json`).

## Project Setup
- DONE: Create a new iPadOS SwiftUI project (iPad-only target) at `ios/LiveRigControlApp.xcodeproj`.
- DONE: Add `mappings.json` to the app bundle.
- DONE: Define models for `Mapping`, `Profile`, `Pad`, `MidiMapping`, `OscMapping` (plus `UiMapping`).
- DONE: Load mappings at launch and expose as app state.
- CI build note: avoid `xcrun --sdk <platform> swift build` (sets `SDKROOT` and can break manifest compilation). Prefer `SDK_PATH="$(xcrun --sdk <platform> --show-sdk-path)"` and `swift build --sdk "$SDK_PATH"` instead.

## UI Parity
- DONE: Profile bar: horizontal list of buttons; active profile state.
- DONE: Grid: `Grid` sized by profile `gridSize`.
- DONE: Pad visual states: `on`/`off` styling, label rendering.
- DONE: Tap handling: toggle vs momentary behavior.
- DONE: Slider UI for variable controls.

## SwiftUI Layout Sketch
Note: Implemented in `ios/Sources/LiveRigControlApp/ContentView.swift`; sketch retained for reference.
```swift
import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var store = MappingStore()

    var body: some View {
        VStack(spacing: 16) {
            ProfileBarView(
                profiles: store.profiles,
                selectedId: store.selectedProfileId,
                onSelect: store.selectProfile
            )

            if let profile = store.selectedProfile {
                PadGridView(
                    profile: profile,
                    padStates: store.padStates,
                    onPadTap: store.handlePadTap
                )
            } else {
                Text("No profile loaded")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .task {
            await store.loadMappings()
        }
    }
}

struct ProfileBarView: View {
    let profiles: [Profile]
    let selectedId: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(profiles) { profile in
                    Button {
                        onSelect(profile.id)
                    } label: {
                        Text(profile.label ?? profile.id)
                            .font(.headline)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(profile.id == selectedId ? .blue : .gray.opacity(0.2))
                            .foregroundStyle(profile.id == selectedId ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

struct PadGridView: View {
  let profile: Profile
  let padStates: [String: Bool]
  let onPadTap: (Pad) -> Void

  var body: some View {
        let rows = profile.gridSize?.last ?? 8
        let cols = profile.gridSize?.first ?? 8
        let matrix = buildPadMatrix(pads: profile.pads, rows: rows, cols: cols)

        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<cols, id: \.self) { col in
                        if let pad = matrix[row][col] {
                            PadView(
                                pad: pad,
                                isOn: padStates[pad.id] ?? false,
                                onTap: { onPadTap(pad) }
                            )
                        } else {
                            Color.clear
                                .frame(minHeight: 64)
                        }
                    }
                }
            }
        }
  }
}

func buildPadMatrix(pads: [Pad], rows: Int, cols: Int) -> [[Pad?]] {
    var matrix = Array(repeating: Array(repeating: nil, count: cols), count: rows)

    for (index, pad) in pads.enumerated() {
        let defaultRow = index / cols
        let defaultCol = index % cols
        let row = pad.row ?? defaultRow
        let col = pad.col ?? defaultCol

        if row >= 0, row < rows, col >= 0, col < cols {
            matrix[row][col] = pad
        }
    }

    return matrix
}

struct PadView: View {
    let pad: Pad
    let isOn: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(pad.label ?? pad.id)
                .frame(maxWidth: .infinity, minHeight: 64)
                .padding(8)
                .background(isOn ? Color.green : Color.gray.opacity(0.2))
                .foregroundStyle(isOn ? .black : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

@MainActor
final class MappingStore: ObservableObject {
    @Published private(set) var mappings: Mapping?
    @Published var selectedProfileId: String?
    @Published var padStates: [String: Bool] = [:]
    @Published var oscEnabled: Bool = false
    @Published var oscHost: String = ""

    private let midi = MidiManager()
    private let osc = OscClient()

    var profiles: [Profile] {
        mappings?.normalizedProfiles() ?? []
    }

    var selectedProfile: Profile? {
        guard let id = selectedProfileId else { return nil }
        return profiles.first { $0.id == id }
    }

    func loadMappings() async {
        guard let url = Bundle.main.url(forResource: "mappings", withExtension: "json") else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(Mapping.self, from: data)
            mappings = decoded
            selectedProfileId = decoded.normalizedProfiles().first?.id
            padStates = [:]
        } catch {
            print("Failed to load mappings.json:", error)
        }
    }

    func selectProfile(_ id: String) {
        selectedProfileId = id
        padStates = [:]
    }

    func handlePadTap(_ pad: Pad) {
        let isOn = padStates[pad.id] ?? false
        let nextState = pad.toggle ? !isOn : true
        padStates[pad.id] = nextState
        sendMidiIfNeeded(for: pad, state: nextState)
        sendOscIfNeeded(for: pad, state: nextState)

        if !pad.toggle {
            padStates[pad.id] = false
        }
    }

    private func sendMidiIfNeeded(for pad: Pad, state: Bool) {
        guard let midi = pad.midi else { return }
        switch midi.type {
        case "note":
            guard let note = midi.note else { return }
            self.midi.sendNote(
                channel: midi.channel,
                note: note,
                onVelocity: midi.onVelocity ?? 100,
                offVelocity: midi.offVelocity ?? 0,
                isOn: state
            )
        case "cc":
            guard let cc = midi.cc else { return }
            let value = state ? (midi.onValue ?? 127) : (midi.offValue ?? 0)
            self.midi.sendCC(
                channel: midi.channel,
                cc: cc,
                value: value
            )
        default:
            break
        }
    }

    private func sendOscIfNeeded(for pad: Pad, state: Bool) {
        guard oscEnabled, pad.osc != nil else { return }
        osc.send(pad: pad, state: state ? "on" : "off")
    }

    func setOscEnabled(_ enabled: Bool) async {
        oscEnabled = enabled
        if enabled {
            await osc.connect(host: oscHost)
        } else {
            osc.disconnect()
        }
    }

    func updateOscHost(_ host: String) async {
        oscHost = host
        if oscEnabled {
            osc.disconnect()
            await osc.connect(host: host)
        }
    }
}
```

## MIDI + OSC Hook Sketch
```swift
final class MidiManager: ObservableObject {
    @Published var outputs: [MidiOutput] = []
    @Published var selectedOutput: MidiOutput?
    private var client = MIDIClientRef()
    private var outPort = MIDIPortRef()

    func refreshOutputs() {
        var results: [MidiOutput] = []
        let count = MIDIGetNumberOfDestinations()

        for index in 0..<count {
            let endpoint = MIDIGetDestination(index)
            var name: Unmanaged<CFString>?
            let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
            let displayName = (status == noErr ? (name?.takeRetainedValue() as String?) : nil) ?? "Output \(index + 1)"
            let output = MidiOutput(id: "\(index)", name: displayName, endpoint: endpoint)
            results.append(output)
        }

        outputs = results
        if selectedOutput == nil {
            selectedOutput = outputs.first
        }
    }

    func sendNote(channel: Int, note: Int, onVelocity: Int, offVelocity: Int, isOn: Bool) {
        guard let output = selectedOutput else { return }
        // TODO: send MIDI Note On/Off via Core MIDI.
    }

    func sendCC(channel: Int, cc: Int, value: Int) {
        guard let output = selectedOutput else { return }
        // TODO: send MIDI CC via Core MIDI.
    }

    func setup() {
        MIDIClientCreate("LiveRigControl" as CFString, midiNotify, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &client)
        MIDIOutputPortCreate(client, "Out" as CFString, &outPort)
        refreshOutputs()
    }

    func sendPacket(bytes: [UInt8]) {
        guard let output = selectedOutput else { return }
        let endpoint = output.endpoint
        var packetList = MIDIPacketList()
        let timeStamp: MIDITimeStamp = 0

        bytes.withUnsafeBytes { buffer in
            var packet = MIDIPacketListInit(&packetList)
            packet = MIDIPacketListAdd(
                &packetList,
                MemoryLayout<MIDIPacketList>.size,
                packet,
                timeStamp,
                buffer.count,
                buffer.bindMemory(to: UInt8.self).baseAddress!
            )

            if packet != nil {
                _ = MIDISend(outPort, endpoint, &packetList)
            }
        }
    }

    deinit {
        if outPort != 0 {
            MIDIPortDispose(outPort)
        }
        if client != 0 {
            MIDIClientDispose(client)
        }
    }
}

final class OscClient: ObservableObject {
    @Published var isConnected: Bool = false
    private var webSocketTask: URLSessionWebSocketTask?
    private var reconnectTask: Task<Void, Never>?

    func makeOscUrl(host: String) -> URL? {
        let resolvedHost = host.isEmpty ? "localhost" : host
        return URL(string: "ws://\(resolvedHost):9001")
    }

    func connect(host: String) async {
        guard let url = makeOscUrl(host: host) else { return }
        if webSocketTask != nil { return }
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        receiveLoop()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    func send(pad: Pad, state: String) {
        guard let socket = webSocketTask else { return }
        guard let osc = pad.osc else { return }
        let payload: [String: Any] = [
            "address": osc.address,
            "args": osc.args ?? [],
            "state": state
        ]
        // TODO: encode payload to JSON and send via WebSocket.
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.receiveLoop()
            case .failure:
                self.isConnected = false
                self.scheduleReconnect()
            }
        }
    }

    private func scheduleReconnect() {
        if reconnectTask != nil { return }
        reconnectTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self.connect()
                if self.isConnected { break }
            }
            self.reconnectTask = nil
        }
    }
}

struct MidiOutput: Identifiable, Hashable {
    let id: String
    let name: String
    let endpoint: MIDIEndpointRef
}

private let midiNotify: MIDINotifyProc = { message, refCon in
    guard let refCon else { return }
    let manager = Unmanaged<MidiManager>.fromOpaque(refCon).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.refreshOutputs()
    }
}
```

## OSC Payload Example
```json
{
  "address": "/rig/scene",
  "args": ["A"],
  "state": "on"
}
```

## Core MIDI Message Sketch
```swift
// Status byte: 0x90 for Note On, 0x80 for Note Off, 0xB0 for CC.
// Channel is 1-16; add (channel - 1) to status.
let noteOnStatus: UInt8 = 0x90 + UInt8(channel - 1)
let noteOffStatus: UInt8 = 0x80 + UInt8(channel - 1)
let ccStatus: UInt8 = 0xB0 + UInt8(channel - 1)

// Example data bytes for Note On: [status, note, velocity]
let bytes: [UInt8] = [noteOnStatus, UInt8(note), UInt8(velocity)]
// TODO: wrap bytes in MIDI packet/list and send via Core MIDI to selected output.
```

## Core MIDI Packet Send Example
```swift
import CoreMIDI

func sendPacket(bytes: [UInt8], to endpoint: MIDIEndpointRef) {
    var packetList = MIDIPacketList()
    let timeStamp: MIDITimeStamp = 0

    bytes.withUnsafeBytes { buffer in
        var packet = MIDIPacketListInit(&packetList)
        packet = MIDIPacketListAdd(
            &packetList,
            MemoryLayout<MIDIPacketList>.size,
            packet,
            timeStamp,
            buffer.count,
            buffer.bindMemory(to: UInt8.self).baseAddress!
        )

        if packet != nil {
            _ = MIDISend(0, endpoint, &packetList)
        }
    }
}
```

## Info.plist Key
```xml
<key>OSC_HOST</key>
<string></string>
```

## OSC Host UI + Persistence Sketch
```swift
struct OscHostField: View {
    @Binding var host: String
    let onCommit: (String) -> Void

    var body: some View {
        TextField("OSC Host (e.g., 192.168.1.10)", text: $host)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .onSubmit {
                onCommit(host.trimmingCharacters(in: .whitespacesAndNewlines))
            }
    }
}

// Persistence idea:
// - Store host in UserDefaults key "osc_host".
// - Default to Info.plist OSC_HOST if UserDefaults is empty.
```

## OSC Host Persistence Helper
```swift
enum OscHostStorage {
    private static let key = "osc_host"

    static func loadDefault() -> String {
        let stored = UserDefaults.standard.string(forKey: key)
        if let stored, !stored.isEmpty {
            return stored
        }
        let plist = Bundle.main.object(forInfoDictionaryKey: "OSC_HOST") as? String
        return plist ?? ""
    }

    static func save(_ host: String) {
        UserDefaults.standard.set(host, forKey: key)
    }
}
```

## MappingStore Init Hook
```swift
@MainActor
final class MappingStore: ObservableObject {
    init() {
        oscHost = OscHostStorage.loadDefault()
    }
}
```

## Model Sketches (Aligned to current JSON)
```swift
struct Mapping: Codable {
    let profiles: [String: Profile]
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
        id = "" // Filled when mapping dictionary is normalized into array.
    }
}

struct Pad: Codable, Identifiable {
    let id: String
    let label: String?
    let row: Int?
    let col: Int?
    let toggle: Bool
    let midi: MidiMapping?
    let osc: OscMapping?
    let notes: String?
}

struct MidiMapping: Codable {
    let type: String // "note" or "cc"
    let channel: Int
    let note: Int?
    let cc: Int?
    let onVelocity: Int?
    let offVelocity: Int?
    let onValue: Int?
    let offValue: Int?
}

struct OscMapping: Codable {
    let address: String
    let args: [CodableValue]?
}

enum CodableValue: Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode(Int.self) { self = .int(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        throw DecodingError.typeMismatch(
            CodableValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported OSC arg type")
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}
```

## Profile Normalization Helper
```swift
extension Mapping {
    func normalizedProfiles() -> [Profile] {
        profiles.map { key, value in
            Profile(id: key, label: value.label, gridSize: value.gridSize, pads: value.pads)
        }
        .sorted { $0.id < $1.id }
    }
}
```

## Core MIDI Integration
- Configure `AVAudioSession` for MIDI use.
- Enumerate MIDI outputs using Core MIDI.
- Provide output picker UI; track selected output.
- Send Note On/Off and CC messages.
- Handle device hot-plug and output list refresh.
- Safely no-op MIDI sends when no output selected.

## OSC Bridge (WebSocket)
- DONE: WebSocket client and OSC JSON payloads matching web app.
- DONE: OSC toggle UI; connect/disconnect + reconnect.
- DONE: Dynamic host-based URL, e.g. `ws://<host>:9001`.
- DONE: OSC sends work when MIDI is unavailable.

## Data + State
- TODO: Persist selected profile, MIDI output, and OSC enabled state.
- DONE: Connection status indicator for OSC (connecting/connected/disconnected + queued).

## Testing
- TODO: iPad Air: app loads, profiles/pads render, taps toggle state.
- TODO: No MIDI device: no errors, UI still functional.
- TODO: With MIDI device: outputs list and messages send correctly.
- TODO: OSC enabled: pad presses send OSC over bridge.

## Prep Work (Before Swift Build)
- TODO: Create a small "known-good" `mappings.json` fixture with 1-2 profiles and a few pads.
- DONE: Document the JSON shape from `src/mappings.json` (updated below).
- DONE: Define OSC payload contract (fields, types, examples).
- DONE: OSC host discovery via Info.plist default + in-app setting + QR input.
- DONE: UI placement for MIDI output picker + OSC toggle with clear empty states.

## UI Placement Sketch (MIDI + OSC)
- Header row under title:
  - Left: MIDI output picker (disabled with label "No MIDI outputs" when empty).
  - Right: Refresh button (disabled if no MIDI or refresh in progress).
- Second row:
  - Left: OSC host field (placeholder "OSC Host", e.g., `192.168.1.10`).
  - Right: OSC toggle with connection status dot (gray = off, green = connected, yellow = connecting).
- Empty states:
  - No MIDI: picker disabled + short helper text "Connect a MIDI device."
  - OSC disconnected: status dot gray; show "Not connected" below toggle.
  - OSC connecting: status dot yellow; block repeated connect attempts.

## Build/Run (SwiftPM, VS Code)
- Open the repo in VS Code and ensure the Swift extension is installed.
- From the terminal:
```sh
cd ios
swift build
```
- Validate mappings:
```sh
swift run MappingValidator --mappings ../src/mappings.json
```
- To run on device, open the folder in Xcode only for signing or use `swift run` with a simulator target once configured.
- Resources (like `mappings.json`) are bundled via `Resources/` in `Package.swift`.

## iOS Pipeline (Signing + Device Run)
- SwiftPM alone cannot install to a device; use Xcode once to create a run target and signing profile.
- Open `ios/Package.swift` in Xcode:
  - File → Open → select `ios/Package.swift`.
  - Select the `LiveRigControlApp` scheme and an iPad device.
  - Set your Team in Signing & Capabilities.
  - Build and run once to create provisioning.
- Keep using VS Code for edits; use Xcode only to deploy.
- If you want to avoid Xcode UI, you can still use it to sign and then run from the toolbar.

## Xcode-Only Checklist
- Add the app identifier and select your Team for signing.
- Enable Local Network and (if needed) Bonjour services in Capabilities.
- Confirm `Info.plist` is attached to the target.
- Choose a device and run once to install/provision.

## GitHub Actions Signing Secrets (Manual Workflow)
- Export a signing certificate from Keychain as `.p12`.
- Base64-encode the `.p12` and your provisioning profile:
```sh
base64 -i cert.p12 | pbcopy
base64 -i profile.mobileprovision | pbcopy
```
- Add GitHub repo secrets:
  - `IOS_SIGNING_CERT_P12` = base64 output of `cert.p12`
  - `IOS_SIGNING_CERT_PASSWORD` = password for the `.p12`
  - `IOS_PROVISION_PROFILE` = base64 output of the `.mobileprovision`

## Testing + Validation (Lightweight)
- DONE: Swift test target for mapping validation (`swift test --enable-swift-testing --filter MappingValidatorTests`).
- TODO: Manual smoke tests:
  - App loads without crash; profiles and pads render.
  - Toggle pads change state; momentary pads hold while pressed.
  - MIDI output selection changes; sending no-ops when empty.
  - OSC connects/disconnects; queue drains after reconnect.
- DONE: Mapping validation tool:
  - `swift run MappingValidator --mappings ../src/mappings.json`

## OSC Host UI + Status (Expanded)
- Field behavior:
  - Trim whitespace on submit.
  - If empty, default to `localhost`.
  - Show inline validation error for malformed host (spaces, protocol prefix).
- Persistence:
  - Save to UserDefaults on submit.
  - Load from UserDefaults, else fall back to Info.plist `OSC_HOST`.
- Connectivity:
  - When OSC toggle flips on, connect immediately with current host.
  - While connecting, disable repeated connect attempts.
  - If connection fails, show status text and allow retry.
- UX niceties:
  - Add a small "Reconnect" button next to the toggle when disconnected.
  - Provide a copyable hint like "ws://HOST:9001" under the field.

## Fixture Draft (mappings.json)
```json
{
  "profiles": {
    "main": {
      "label": "Main",
      "gridSize": [4, 3],
      "pads": [
        {
          "id": "scene-a",
          "label": "Scene A",
          "toggle": true,
          "midi": { "type": "note", "channel": 1, "note": 36, "onVelocity": 100 },
          "osc": { "address": "/rig/scene", "args": ["A"] }
        },
        {
          "id": "scene-b",
          "label": "Scene B",
          "toggle": true,
          "midi": { "type": "note", "channel": 1, "note": 37, "onVelocity": 100 },
          "osc": { "address": "/rig/scene", "args": ["B"] }
        },
        {
          "id": "strobe",
          "label": "Strobe",
          "toggle": false,
          "midi": { "type": "cc", "channel": 1, "cc": 20, "onValue": 127, "offValue": 0 },
          "osc": { "address": "/rig/strobe", "args": [] }
        },
        {
          "id": "blue",
          "label": "Blue",
          "row": 2,
          "col": 3,
          "toggle": true,
          "midi": { "type": "note", "channel": 1, "note": 40, "onVelocity": 100 },
          "osc": { "address": "/rig/color", "args": ["blue"] }
        }
      ]
    },
    "alt": {
      "label": "Alt",
      "gridSize": [3, 2],
      "pads": [
        {
          "id": "flash",
          "label": "Flash",
          "toggle": false,
          "midi": { "type": "note", "channel": 1, "note": 45, "onVelocity": 120 },
          "osc": { "address": "/rig/flash", "args": [] }
        }
      ]
    }
  }
}
```

## Current mappings.json Shape (from src/mappings.json)
- Top-level object with `profiles` map keyed by profile id (string).
- Each profile object:
  - `label` (string, optional)
  - `gridSize` (array of two ints: `[cols, rows]`)
  - `pads` (array)
- Each pad object:
  - `id` (string)
  - `label` (string, optional)
  - `row` / `col` (int, optional; zero-based)
  - `toggle` (bool, optional)
  - `mode` (string, optional: `toggle` or `momentary`)
  - `group` (string or object, optional)
  - `midi` (object, optional)
  - `osc` (object, optional)
  - `ui` (object, optional)
  - `notes` (string, optional; comments only)
- MIDI object (when present):
  - `type` ("note" | "cc" | "program" | "realtime")
  - `channel` (int, 1-16; required for note/cc/program)
  - For notes: `note` (int), `onVelocity` (int), `offVelocity` (int)
  - For CC: `cc` (int), `onValue` (int), `offValue` (int)
  - For program: `program` (int), `bankMsb` (int), `bankLsb` (int), `programBankMode` (string)
  - For realtime: `realtime` ("start" | "continue" | "stop")
- OSC object (when present):
  - `address` (string)
  - `args` (array, optional; ints/strings)
- UI object (when present):
  - `type` ("button" | "slider")
  - `role` ("velocity" | "velocityOverride" | "pattern" | "patternBank", optional)
  - `min` / `max` / `step` / `initial` (ints, optional)
  - `showValue` (bool, optional)
  - `target` (string, optional; for velocity overrides)
  - `bank` (int, optional; for pattern bank toggles)

## OSC Payload Contract
- Transport: WebSocket JSON message.
- Payload fields:
  - `address` (string)
  - `args` (array, optional; passthrough from mapping)
  - `state` (string: "on" or "off")
- Example:
```json
{
  "address": "/rig/scene",
  "args": ["A"],
  "state": "on"
}
```

## Permissions Plan
- Local Network: required to reach the OSC bridge on another device; enable the Local Network entitlement and provide a clear usage description.
- Bonjour (optional): only if you choose to discover the OSC host via Bonjour/mDNS; define service type and add the Bonjour service list entry.
- MIDI: Core MIDI does not require user permission prompts, but still ensure audio session configuration is correct.
- Background execution: avoid unless you need OSC/MIDI while app is backgrounded; if needed, add audio background mode and keep-alive strategy.
- Privacy strings: add `NSLocalNetworkUsageDescription` and, if using Bonjour, `NSBonjourServices`.

## Info.plist Permissions Example
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Connect to the OSC bridge on your local network.</string>
<key>NSBonjourServices</key>
<array>
  <string>_osc._udp</string>
  <string>_osc._tcp</string>
</array>
```

## ATS (App Transport Security) Note
- `ws://` may be blocked by ATS unless you add an exception for local network traffic.
- Using `wss://` avoids ATS exceptions but requires a valid TLS setup on the OSC bridge host.
- For local rigs, consider a scoped `NSExceptionDomains` entry for your OSC host or LAN IP range.
