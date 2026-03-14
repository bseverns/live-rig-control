import Foundation

@MainActor
final class MappingStore: ObservableObject {
    private static let selectedProfileKey = "selected_profile_id"
    private static let oscEnabledKey = "osc_enabled"

    @Published private(set) var mappings: Mapping?
    @Published var selectedProfileId: String?
    @Published var padStates: [String: Bool] = [:]
    @Published var oscEnabled: Bool = false
    @Published var oscHost: String = ""
    @Published var oscHostError: String?
    @Published var oscHostHint: String?
    @Published var profileIssues: [String: [String]] = [:]
    @Published var sliderValues: [String: Int] = [:]
    @Published var isLoading: Bool = true
    private var overlayDeadline: TimeInterval?

    let midi = MidiManager()
    let osc = OscClient()
    let logs = LogStore()
    private var profileControls: [String: ProfileControlState] = [:]
    private var preferredProfileId: String?
    private var lastSliderSend: [String: TimeInterval] = [:]
    private let sliderSendInterval: TimeInterval = 0.02
    private var pendingSliderValues: [String: Int] = [:]
    private var pendingSliderWorkItems: [String: DispatchWorkItem] = [:]

    init() {
        let now = ProcessInfo.processInfo.systemUptime
        overlayDeadline = now + 0.8
        preferredProfileId = UserDefaults.standard.string(forKey: Self.selectedProfileKey)
        oscEnabled = UserDefaults.standard.bool(forKey: Self.oscEnabledKey)
        oscHost = OscHostStorage.loadDefault()
        osc.onEvent = { [weak self] message in
            self?.logs.add(message)
        }
        midi.onEvent = { [weak self] message in
            self?.logs.add(message)
        }
        midi.setup()

        if oscEnabled {
            Task { [weak self] in
                await self?.setOscEnabled(true)
            }
        }
    }

    var profiles: [Profile] {
        mappings?.normalizedProfiles() ?? []
    }

    var selectedProfile: Profile? {
        guard let id = selectedProfileId else { return nil }
        return profiles.first { $0.id == id }
    }

    func loadMappings() async {
        isLoading = true
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: "mappings", withExtension: "json")
            ?? Bundle.main.url(forResource: "mappings", withExtension: "json")
        #else
        let url = Bundle.main.url(forResource: "mappings", withExtension: "json")
        #endif
        guard let url else {
            finishLoading()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(Mapping.self, from: data)
            mappings = decoded
            let profiles = decoded.normalizedProfiles()
            if let preferredProfileId,
               profiles.contains(where: { $0.id == preferredProfileId }) {
                selectedProfileId = preferredProfileId
            } else {
                selectedProfileId = profiles.first?.id
            }
            if let selectedProfileId {
                UserDefaults.standard.set(selectedProfileId, forKey: Self.selectedProfileKey)
            }
            padStates = [:]
            sliderValues = [:]
            logs.add("Loaded mappings.json")
            validateProfiles(profiles)
            syncPatternBankState()
        } catch {
            logs.add("Failed to load mappings.json: \(error.localizedDescription)")
            print("Failed to load mappings.json:", error)
        }
        finishLoading()
    }

    func selectProfile(_ id: String) {
        selectedProfileId = id
        UserDefaults.standard.set(id, forKey: Self.selectedProfileKey)
        padStates = [:]
        sliderValues = [:]
        syncPatternBankState()
    }

    func handlePadTap(_ pad: Pad) {
        guard pad.isToggle else { return }
        if pad.ui?.role == "patternBank" {
            handlePatternBankTap(pad)
            return
        }
        let isOn = padStates[pad.id] ?? false
        let nextState = !isOn
        padStates[pad.id] = nextState

        logs.add("Pad \(pad.id) \(nextState ? "on" : "off")")
        sendMidiIfNeeded(for: pad, state: nextState)
        sendOscIfNeeded(for: pad, state: nextState)
    }

    func handlePadPress(_ pad: Pad) {
        guard !pad.isToggle else { return }
        let isOn = padStates[pad.id] ?? false
        if isOn { return }
        padStates[pad.id] = true
        logs.add("Pad \(pad.id) on")
        sendMidiIfNeeded(for: pad, state: true)
        sendOscIfNeeded(for: pad, state: true)
    }

    func handlePadRelease(_ pad: Pad) {
        guard !pad.isToggle else { return }
        let isOn = padStates[pad.id] ?? false
        if !isOn { return }
        padStates[pad.id] = false
        logs.add("Pad \(pad.id) off")
        sendMidiIfNeeded(for: pad, state: false)
        sendOscIfNeeded(for: pad, state: false)
    }

    func sliderValue(for pad: Pad) -> Int {
        if pad.ui?.role == "velocity" {
            return profileControlState(for: selectedProfileId).velocity
        }
        if pad.ui?.role == "velocityOverride" {
            if let target = pad.ui?.target {
                let override = profileControlState(for: selectedProfileId).velocityOverrides[target]
                if let override { return override }
            }
            return profileControlState(for: selectedProfileId).velocity
        }
        if let value = sliderValues[pad.id] {
            return value
        }
        let minValue = pad.ui?.min ?? 0
        let maxValue = pad.ui?.max ?? 127
        let initial = pad.ui?.initial ?? pad.midi?.offValue ?? minValue
        return Swift.min(maxValue, Swift.max(minValue, initial))
    }

    func handleSliderChange(_ pad: Pad, value: Int) {
        let minValue = pad.ui?.min ?? 0
        let maxValue = pad.ui?.max ?? 127
        var clamped = Swift.min(maxValue, Swift.max(minValue, value))

        if pad.ui?.role == "velocity" {
            setProfileVelocity(clamped, for: selectedProfileId)
            sliderValues[pad.id] = clamped
            return
        }

        if pad.ui?.role == "velocityOverride" {
            if let target = pad.ui?.target {
                setProfileVelocityOverride(clamped, for: selectedProfileId, target: target)
            }
            sliderValues[pad.id] = clamped
            return
        }

        if pad.ui?.role == "pattern" {
            if profileControlState(for: selectedProfileId).patternBank == 1 {
                clamped = Swift.min(clamped, 121)
            }
            sliderValues[pad.id] = clamped
            sendProgramChangeForPad(pad, program: clamped)
            return
        }

        sliderValues[pad.id] = clamped
        if let midiMapping = pad.midi {
            sendSliderValue(for: pad, midiMapping: midiMapping, value: clamped)
        }
        if pad.osc != nil {
            sendOscValueIfNeeded(for: pad, value: clamped)
        }
    }

    func setOscEnabled(_ enabled: Bool) async {
        oscEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.oscEnabledKey)
        if enabled {
            logs.add("OSC enabled")
            await osc.connect(host: oscHost)
        } else {
            logs.add("OSC disabled")
            osc.disconnect()
        }
    }

    func updateOscHost(_ host: String) async {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = sanitizeOscHost(trimmed)
        oscHost = sanitized
        oscHostError = validateOscHost(sanitized)
        oscHostHint = sanitized != trimmed ? "Host normalized to \(sanitized)" : nil
        if oscHostError != nil {
            logs.add("OSC host invalid")
            return
        }
        OscHostStorage.save(sanitized)
        logs.add("OSC host set to \(sanitized.isEmpty ? "localhost" : sanitized)")
        if oscEnabled {
            osc.disconnect()
            await osc.connect(host: sanitized)
        }
    }

    func updateOscHostFromQr(_ payload: String) async {
        let host = extractHost(from: payload)
        await updateOscHost(host)
    }

    private func sendMidiIfNeeded(for pad: Pad, state: Bool) {
        guard let midiMapping = pad.midi else { return }
        switch midiMapping.type {
        case "note":
            guard let note = midiMapping.note else { return }
            let velocityOverride = profileControlState(for: selectedProfileId).velocityOverrides[pad.id]
            let velocity = velocityOverride ?? midiMapping.onVelocity ?? profileControlState(for: selectedProfileId).velocity
            logs.add("MIDI note \(note) ch \(midiMapping.channel) \(state ? "on" : "off")")
            midi.sendNote(
                channel: midiMapping.channel,
                note: note,
                onVelocity: velocity,
                offVelocity: midiMapping.offVelocity ?? 0,
                isOn: state
            )
        case "cc":
            guard let cc = midiMapping.cc else { return }
            let value = state ? (midiMapping.onValue ?? 127) : (midiMapping.offValue ?? 0)
            logs.add("MIDI CC \(cc) ch \(midiMapping.channel) = \(value)")
            midi.sendCC(
                channel: midiMapping.channel,
                cc: cc,
                value: value
            )
        case "program":
            guard state else { return }
            let program = midiMapping.program ?? 1
            sendProgramChangeForPad(pad, program: program)
        case "realtime":
            guard state else { return }
            if let message = midiMapping.realtime {
                logs.add("MIDI realtime \(message)")
                midi.sendRealtime(message)
            }
        default:
            break
        }
    }

    private func sendProgramChangeForPad(_ pad: Pad, program: Int) {
        guard let midiMapping = pad.midi else { return }
        var bankMsb = midiMapping.bankMsb
        var bankLsb = midiMapping.bankLsb
        var safeProgram = program

        if midiMapping.programBankMode == "electribePattern" {
            let bank = profileControlState(for: selectedProfileId).patternBank
            bankMsb = 0
            bankLsb = bank
            if bank == 1 {
                safeProgram = min(program, 121)
            }
        }
        logs.add("MIDI program \(safeProgram) ch \(midiMapping.channel)")
        midi.sendProgramChange(
            channel: midiMapping.channel,
            program: safeProgram,
            bankMsb: bankMsb,
            bankLsb: bankLsb
        )
    }

    private func handlePatternBankTap(_ pad: Pad) {
        guard let bank = pad.ui?.bank else { return }
        setProfilePatternBank(bank, for: selectedProfileId)
        syncPatternBankState()
    }

    private func syncPatternBankState() {
        guard let profile = selectedProfile else { return }
        let bank = profileControlState(for: selectedProfileId).patternBank
        for other in profile.pads {
            guard other.ui?.role == "patternBank" else { continue }
            let isOn = other.ui?.bank == bank
            padStates[other.id] = isOn
        }
    }

    private func profileControlState(for profileId: String?) -> ProfileControlState {
        let key = profileId ?? "_"
        if let existing = profileControls[key] {
            return existing
        }
        let initial = ProfileControlState()
        profileControls[key] = initial
        return initial
    }

    private func setProfileVelocity(_ value: Int, for profileId: String?) {
        let key = profileId ?? "_"
        var state = profileControlState(for: profileId)
        state.velocity = value
        profileControls[key] = state
    }

    private func setProfileVelocityOverride(_ value: Int, for profileId: String?, target: String) {
        let key = profileId ?? "_"
        var state = profileControlState(for: profileId)
        state.velocityOverrides[target] = value
        profileControls[key] = state
    }

    private func setProfilePatternBank(_ value: Int, for profileId: String?) {
        let key = profileId ?? "_"
        var state = profileControlState(for: profileId)
        state.patternBank = value
        profileControls[key] = state
    }

    private func sendOscIfNeeded(for pad: Pad, state: Bool) {
        guard oscEnabled, pad.osc != nil else { return }
        osc.send(pad: pad, state: state ? "on" : "off")
    }

    private func sendOscValueIfNeeded(for pad: Pad, value: Int) {
        guard oscEnabled, pad.osc != nil else { return }
        osc.send(pad: pad, value: value)
    }

    private func validateOscHost(_ host: String) -> String? {
        if host.isEmpty {
            return nil
        }
        if host.contains(where: { $0.isWhitespace }) {
            return "OSC endpoint cannot contain spaces."
        }
        if host.contains("://") {
            guard let components = URLComponents(string: host),
                  let scheme = components.scheme?.lowercased() else {
                return "Use a plain host or ws:// / udp:// endpoint."
            }
            if ["ws", "wss", "udp", "osc"].contains(scheme) == false {
                return "Supported OSC endpoint schemes: ws, wss, udp, osc."
            }
            guard components.host?.isEmpty == false else {
                return "OSC endpoint must include a host."
            }
            if let path = components.percentEncodedPath.removingPercentEncoding,
               path.isEmpty == false, path != "/" {
                return "OSC endpoint cannot include a path."
            }
            return nil
        }
        if host.contains("/") {
            return "Host cannot include paths. Use udp://host:port for OSC UDP."
        }
        return nil
    }

    private func sanitizeOscHost(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("://") else {
            return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let endpointHost = components.host,
              endpointHost.isEmpty == false else {
            return trimmed
        }
        var value = "\(scheme)://\(endpointHost)"
        if let port = components.port {
            value += ":\(port)"
        }
        return value
    }

    private func extractHost(from payload: String) -> String {
        if let components = URLComponents(string: payload),
           let host = components.host {
            if let scheme = components.scheme {
                var value = "\(scheme.lowercased())://\(host)"
                if let port = components.port {
                    value += ":\(port)"
                }
                return value
            }
            return host
        }
        return payload
    }

    private func validateProfiles(_ profiles: [Profile]) {
        var issues: [String: [String]] = [:]
        for profile in profiles {
            issues[profile.id] = validateProfile(profile)
        }
        profileIssues = issues
    }

    private func validateProfile(_ profile: Profile) -> [String] {
        var messages: [String] = []
        let cols = max(profile.gridSize?.first ?? 8, 1)
        let rows = max(profile.gridSize?.last ?? 8, 1)
        if profile.gridSize == nil {
            messages.append("Missing gridSize; defaulting to 8x8.")
        }

        var occupied = Set<String>()
        for (index, pad) in profile.pads.enumerated() {
            let defaultRow = index / cols
            let defaultCol = index % cols
            let row = pad.row ?? defaultRow
            let col = pad.col ?? defaultCol

            if row < 0 || row >= rows || col < 0 || col >= cols {
                messages.append("Pad \(pad.id) out of bounds (\(row),\(col)) for \(cols)x\(rows).")
                continue
            }

            let key = "\(row),\(col)"
            if occupied.contains(key) {
                messages.append("Pad collision at (\(row),\(col)).")
            } else {
                occupied.insert(key)
            }
        }

        if !messages.isEmpty {
            logs.add("Profile \(profile.id) has \(messages.count) issue(s)")
        }
        return messages
    }

    private func finishLoading() {
        let now = ProcessInfo.processInfo.systemUptime
        let deadline = overlayDeadline ?? now
        let delay = max(0, deadline - now)
        if delay == 0 {
            isLoading = false
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.isLoading = false
            }
        }
    }

    private func sendSliderValue(for pad: Pad, midiMapping: MidiMapping, value: Int) {
        let now = ProcessInfo.processInfo.systemUptime
        let last = lastSliderSend[pad.id] ?? 0
        let elapsed = now - last

        if elapsed >= sliderSendInterval {
            lastSliderSend[pad.id] = now
            sendMidiForSlider(pad: pad, midiMapping: midiMapping, value: value)
            return
        }

        pendingSliderValues[pad.id] = value
        if pendingSliderWorkItems[pad.id] == nil {
            let delay = max(sliderSendInterval - elapsed, 0.0)
            let work = DispatchWorkItem { [weak self] in
                self?.flushPendingSlider(for: pad.id, midiMapping: midiMapping)
            }
            pendingSliderWorkItems[pad.id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func flushPendingSlider(for padId: String, midiMapping: MidiMapping) {
        pendingSliderWorkItems[padId] = nil
        guard let value = pendingSliderValues.removeValue(forKey: padId) else { return }
        lastSliderSend[padId] = ProcessInfo.processInfo.systemUptime
        sendMidiForSlider(padId: padId, midiMapping: midiMapping, value: value)
    }

    private func sendMidiForSlider(pad: Pad, midiMapping: MidiMapping, value: Int) {
        sendMidiForSlider(padId: pad.id, midiMapping: midiMapping, value: value)
    }

    private func sendMidiForSlider(padId: String, midiMapping: MidiMapping, value: Int) {
        switch midiMapping.type {
        case "cc":
            guard let cc = midiMapping.cc else { return }
            midi.sendCC(channel: midiMapping.channel, cc: cc, value: value)
            logs.add("MIDI CC \(cc) ch \(midiMapping.channel) = \(value)")
        case "program":
            sendProgramChangeForPadId(padId, midiMapping: midiMapping, program: value)
        default:
            break
        }
    }

    private func sendProgramChangeForPadId(_ padId: String, midiMapping: MidiMapping, program: Int) {
        let mode = midiMapping.programBankMode ?? "none"
        let bankMsb: Int?
        let bankLsb: Int?
        switch mode {
        case "msb":
            bankMsb = midiMapping.bankMsb
            bankLsb = nil
        case "lsb":
            bankMsb = nil
            bankLsb = midiMapping.bankLsb
        case "both":
            bankMsb = midiMapping.bankMsb
            bankLsb = midiMapping.bankLsb
        default:
            bankMsb = nil
            bankLsb = nil
        }
        midi.sendProgramChange(channel: midiMapping.channel, program: program, bankMsb: bankMsb, bankLsb: bankLsb)
        logs.add("MIDI Program ch \(midiMapping.channel) = \(program)")
    }
}

private struct ProfileControlState {
    var velocity: Int = 100
    var patternBank: Int = 0
    var velocityOverrides: [String: Int] = [:]
}
