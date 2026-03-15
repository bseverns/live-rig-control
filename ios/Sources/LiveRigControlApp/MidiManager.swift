import AVFoundation
import CoreMIDI
import Foundation

@MainActor
final class MidiManager: ObservableObject {
    private static let selectedOutputKey = "midi_output_id"

    @Published var outputs: [MidiOutput] = []
    @Published var selectedOutputId: String = UserDefaults.standard.string(forKey: MidiManager.selectedOutputKey) ?? "" {
        didSet {
            UserDefaults.standard.set(selectedOutputId, forKey: MidiManager.selectedOutputKey)
        }
    }
    var onEvent: ((String) -> Void)?

    private var client = MIDIClientRef()
    private var outPort = MIDIPortRef()

    func setup() {
        configureAudioSession()
        #if targetEnvironment(simulator)
        outputs = []
        selectedOutputId = ""
        onEvent?("MIDI unavailable in iOS Simulator")
        #else
        MIDIClientCreate("LiveRigControl" as CFString, midiNotify, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &client)
        MIDIOutputPortCreate(client, "Out" as CFString, &outPort)
        refreshOutputs()
        #endif
    }

    func refreshOutputs() {
        #if targetEnvironment(simulator)
        outputs = []
        selectedOutputId = ""
        #else
        var results: [MidiOutput] = []
        let count = MIDIGetNumberOfDestinations()

        for index in 0..<count {
            let endpoint = MIDIGetDestination(index)
            let name = MidiManager.endpointName(endpoint, fallback: "Output \(index + 1)")
            let id = MidiManager.endpointId(endpoint, fallback: "\(index)")
            let output = MidiOutput(id: id, name: name, endpoint: endpoint)
            results.append(output)
        }

        outputs = results
        if outputs.contains(where: { $0.id == selectedOutputId }) == false {
            selectedOutputId = outputs.first?.id ?? ""
        }
        onEvent?("MIDI outputs: \(outputs.count)")
        #endif
    }

    func sendNote(channel: Int, note: Int, onVelocity: Int, offVelocity: Int, isOn: Bool) {
        let safeChannel = clampChannel(channel)
        let safeNote = clampDataByte(note)
        let rawVelocity = isOn ? onVelocity : offVelocity
        let safeVelocity = clampDataByte(rawVelocity)
        logClampIfNeeded(label: "channel", original: channel, clamped: safeChannel)
        logClampIfNeeded(label: "note", original: note, clamped: safeNote)
        logClampIfNeeded(label: "velocity", original: rawVelocity, clamped: safeVelocity)
        let status: UInt8 = (isOn ? 0x90 : 0x80) + UInt8(safeChannel - 1)
        let bytes: [UInt8] = [status, UInt8(safeNote), UInt8(safeVelocity)]
        sendPacket(bytes: bytes)
    }

    func sendCC(channel: Int, cc: Int, value: Int) {
        let safeChannel = clampChannel(channel)
        let safeCc = clampDataByte(cc)
        let safeValue = clampDataByte(value)
        logClampIfNeeded(label: "channel", original: channel, clamped: safeChannel)
        logClampIfNeeded(label: "cc", original: cc, clamped: safeCc)
        logClampIfNeeded(label: "value", original: value, clamped: safeValue)
        let status: UInt8 = 0xB0 + UInt8(safeChannel - 1)
        let bytes: [UInt8] = [status, UInt8(safeCc), UInt8(safeValue)]
        sendPacket(bytes: bytes)
    }

    func sendProgramChange(channel: Int, program: Int, bankMsb: Int?, bankLsb: Int?) {
        let safeChannel = clampChannel(channel)
        let safeProgram = clampDataByte(program)
        logClampIfNeeded(label: "channel", original: channel, clamped: safeChannel)
        logClampIfNeeded(label: "program", original: program, clamped: safeProgram)
        if let bankMsb {
            let safeMsb = clampDataByte(bankMsb)
            logClampIfNeeded(label: "bankMsb", original: bankMsb, clamped: safeMsb)
            let status: UInt8 = 0xB0 + UInt8(safeChannel - 1)
            sendPacket(bytes: [status, 0x00, UInt8(safeMsb)])
        }
        if let bankLsb {
            let safeLsb = clampDataByte(bankLsb)
            logClampIfNeeded(label: "bankLsb", original: bankLsb, clamped: safeLsb)
            let status: UInt8 = 0xB0 + UInt8(safeChannel - 1)
            sendPacket(bytes: [status, 0x20, UInt8(safeLsb)])
        }
        let status: UInt8 = 0xC0 + UInt8(safeChannel - 1)
        sendPacket(bytes: [status, UInt8(safeProgram)])
    }

    func sendRealtime(_ message: String) {
        let status: UInt8?
        switch message {
        case "start":
            status = 0xFA
        case "continue":
            status = 0xFB
        case "stop":
            status = 0xFC
        default:
            status = nil
        }
        guard let status else { return }
        sendPacket(bytes: [status])
    }

    func sendPacket(bytes: [UInt8]) {
        #if targetEnvironment(simulator)
        onEvent?("MIDI send ignored in simulator")
        #else
        guard let output = outputs.first(where: { $0.id == selectedOutputId }) else {
            onEvent?("MIDI no output selected")
            return
        }
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
            _ = MIDISend(outPort, endpoint, &packetList)
        }
        #endif
    }

    deinit {
        if outPort != 0 {
            MIDIPortDispose(outPort)
        }
        if client != 0 {
            MIDIClientDispose(client)
        }
    }

    private static func endpointName(_ endpoint: MIDIEndpointRef, fallback: String) -> String {
        var name: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
        if status == noErr, let value = name?.takeRetainedValue() {
            return value as String
        }
        return fallback
    }

    private static func endpointId(_ endpoint: MIDIEndpointRef, fallback: String) -> String {
        var uniqueId: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueId)
        if status == noErr {
            return String(uniqueId)
        }
        return fallback
    }

    private func validateChannel(_ channel: Int) -> Bool {
        channel >= 1 && channel <= 16
    }

    private func validateDataByte(_ value: Int) -> Bool {
        value >= 0 && value <= 127
    }

    private func clampChannel(_ channel: Int) -> Int {
        min(16, max(1, channel))
    }

    private func clampDataByte(_ value: Int) -> Int {
        min(127, max(0, value))
    }

    private func logClampIfNeeded(label: String, original: Int, clamped: Int) {
        guard original != clamped else { return }
        onEvent?("MIDI clamped \(label): \(original) -> \(clamped)")
    }

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            onEvent?("AVAudioSession configured")
        } catch {
            onEvent?("AVAudioSession error: \(error.localizedDescription)")
        }
        #else
        onEvent?("AVAudioSession not available on macOS")
        #endif
    }
}

struct MidiOutput: Identifiable, Hashable {
    let id: String
    let name: String
    let endpoint: MIDIEndpointRef
}

private let midiNotify: MIDINotifyProc = { _, refCon in
    guard let refCon else { return }
    let manager = Unmanaged<MidiManager>.fromOpaque(refCon).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.refreshOutputs()
    }
}
