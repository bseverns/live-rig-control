import AVFoundation
import CoreMIDI
import Foundation

@MainActor
final class MidiManager: ObservableObject {
    @Published var outputs: [MidiOutput] = []
    @Published var selectedOutputId: String = ""
    var onEvent: ((String) -> Void)?

    private var client = MIDIClientRef()
    private var outPort = MIDIPortRef()

    func setup() {
        configureAudioSession()
        MIDIClientCreate("LiveRigControl" as CFString, midiNotify, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &client)
        MIDIOutputPortCreate(client, "Out" as CFString, &outPort)
        refreshOutputs()
    }

    func refreshOutputs() {
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

    func sendPacket(bytes: [UInt8]) {
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
