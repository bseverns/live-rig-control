import AVFoundation
import CoreMIDI
import Darwin
import Foundation

@MainActor
final class MidiManager: ObservableObject {
    private static let selectedOutputKey = "midi_output_id"
    private static let virtualSourceDisplayName = "LiveRigControl"

    @Published var outputs: [MidiOutput] = []
    @Published var isVirtualSourceActive = false
    @Published var virtualSourceName = MidiManager.virtualSourceDisplayName
    @Published var selectedOutputId: String = UserDefaults.standard.string(forKey: MidiManager.selectedOutputKey) ?? "" {
        didSet {
            UserDefaults.standard.set(selectedOutputId, forKey: MidiManager.selectedOutputKey)
        }
    }
    var onEvent: ((String) -> Void)?

    private var client = MIDIClientRef()
    private var outPort = MIDIPortRef()
    private var virtualSource = MIDIEndpointRef()
    private var networkSessionObserver: NSObjectProtocol?
    private var networkContactsObserver: NSObjectProtocol?

    func setup() {
        configureAudioSession()
        #if targetEnvironment(simulator)
        outputs = []
        selectedOutputId = ""
        isVirtualSourceActive = false
        onEvent?("MIDI unavailable in iOS Simulator")
        #else
        configureNetworkSession()
        startObservingNetworkSession()

        let clientStatus = MIDIClientCreate(
            "LiveRigControl" as CFString,
            midiNotify,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &client
        )
        guard clientStatus == noErr else {
            onEvent?("MIDI client create failed: \(clientStatus)")
            return
        }

        let sourceStatus = MIDISourceCreate(
            client,
            MidiManager.virtualSourceDisplayName as CFString,
            &virtualSource
        )
        guard sourceStatus == noErr else {
            onEvent?("MIDI virtual source create failed: \(sourceStatus)")
            return
        }
        isVirtualSourceActive = true
        virtualSourceName = MidiManager.endpointName(virtualSource, fallback: MidiManager.virtualSourceDisplayName)
        onEvent?("MIDI virtual source: \(virtualSourceName)")

        let portStatus = MIDIOutputPortCreate(client, "Out" as CFString, &outPort)
        if portStatus != noErr {
            onEvent?("MIDI output port create failed: \(portStatus)")
        }

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
        let localNetworkDestinationId = MidiManager.endpointId(
            MIDINetworkSession.default().destinationEndpoint(),
            fallback: ""
        )

        for index in 0..<count {
            let endpoint = MIDIGetDestination(index)
            let name = MidiManager.endpointName(endpoint, fallback: "Output \(index + 1)")
            let id = MidiManager.endpointId(endpoint, fallback: "\(index)")
            let output = MidiOutput(
                id: id,
                name: name,
                endpoint: endpoint,
                isLocalNetworkSession: id == localNetworkDestinationId
            )
            results.append(output)
        }

        outputs = results
        let currentSelection = outputs.first(where: { $0.id == selectedOutputId })
        let preferredRemoteOutput = outputs.first(where: { $0.isLocalNetworkSession == false })

        if currentSelection == nil {
            selectedOutputId = preferredRemoteOutput?.id ?? outputs.first?.id ?? ""
        } else if currentSelection?.isLocalNetworkSession == true, let preferredRemoteOutput {
            selectedOutputId = preferredRemoteOutput.id
        }
        let outputNames = outputs.map(\.name).joined(separator: ", ")
        if outputNames.isEmpty {
            onEvent?("MIDI outputs: 0")
        } else {
            onEvent?("MIDI outputs: \(outputs.count) [\(outputNames)]")
        }
        if let selected = outputs.first(where: { $0.id == selectedOutputId }) {
            onEvent?("MIDI selected output: \(selected.name)")
        }
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
        var packetList = MIDIPacketList()
        let timeStamp = MIDITimeStamp(mach_absolute_time())

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

            var publishedToVirtualSource = false
            if virtualSource != 0 {
                let status = MIDIReceived(virtualSource, &packetList)
                if status != noErr {
                    onEvent?("MIDI virtual source send failed: \(status)")
                } else {
                    publishedToVirtualSource = true
                    onEvent?("MIDI published \(bytes.count) byte(s) from \(virtualSourceName)")
                }
            }

            guard let output = outputs.first(where: { $0.id == selectedOutputId }) else {
                if publishedToVirtualSource == false {
                    onEvent?("MIDI no output selected")
                }
                return
            }
            guard outPort != 0 else {
                onEvent?("MIDI output port unavailable")
                return
            }

            let status = MIDISend(outPort, output.endpoint, &packetList)
            if status != noErr {
                onEvent?("MIDI output send failed: \(status)")
            } else {
                onEvent?("MIDI sent \(bytes.count) byte(s) to \(output.name)")
            }
        }
        #endif
    }

    deinit {
        if let networkSessionObserver {
            NotificationCenter.default.removeObserver(networkSessionObserver)
        }
        if let networkContactsObserver {
            NotificationCenter.default.removeObserver(networkContactsObserver)
        }
        if outPort != 0 {
            MIDIPortDispose(outPort)
        }
        if virtualSource != 0 {
            MIDIEndpointDispose(virtualSource)
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

    private func configureNetworkSession() {
        let session = MIDINetworkSession.default()
        if session.isEnabled == false {
            session.isEnabled = true
        }
        session.connectionPolicy = .hostsInContactList

        let displayName = session.localName.isEmpty ? "Session 1" : session.localName
        onEvent?("Network MIDI enabled for hosts in the contact list: \(displayName) port \(session.networkPort)")

        let sourceName = MidiManager.endpointName(session.sourceEndpoint(), fallback: "Network Source")
        let destinationName = MidiManager.endpointName(session.destinationEndpoint(), fallback: "Network Destination")
        onEvent?("Network MIDI endpoints: src=\(sourceName) dst=\(destinationName)")

        let connectionCount = session.connections().count
        if connectionCount > 0 {
            onEvent?("Network MIDI connections: \(connectionCount)")
        }
    }

    private func startObservingNetworkSession() {
        let center = NotificationCenter.default
        networkSessionObserver = center.addObserver(
            forName: Notification.Name(rawValue: MIDINetworkNotificationSessionDidChange),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let session = MIDINetworkSession.default()
                self.onEvent?("Network MIDI session changed: \(session.connections().count) connection(s)")
                self.refreshOutputs()
            }
        }

        networkContactsObserver = center.addObserver(
            forName: Notification.Name(rawValue: MIDINetworkNotificationContactsDidChange),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onEvent?("Network MIDI contacts changed")
            }
        }
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
    let isLocalNetworkSession: Bool
}

private let midiNotify: MIDINotifyProc = { _, refCon in
    guard let refCon else { return }
    let manager = Unmanaged<MidiManager>.fromOpaque(refCon).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.refreshOutputs()
    }
}
