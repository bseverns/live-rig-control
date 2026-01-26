import SwiftUI

#if canImport(UIKit)
import UIKit

struct HapticFeedback {
    private let generator = UIImpactFeedbackGenerator(style: .light)

    func impactOccurred() {
        generator.impactOccurred()
    }
}
#else
struct HapticFeedback {
    func impactOccurred() {}
}
#endif

struct ContentView: View {
    @StateObject private var store = MappingStore()

    var body: some View {
        VStack(spacing: 16) {
            Text("Live Rig Control")
                .font(.largeTitle)
                .bold()

            ConnectionBarView(store: store, midi: store.midi, osc: store.osc)

            LogPanelView(logs: store.logs)

            ProfileBarView(
                profiles: store.profiles,
                selectedId: store.selectedProfileId,
                issues: store.profileIssues,
                onSelect: store.selectProfile
            )

            ProfileIssuesView(
                profileId: store.selectedProfileId,
                issues: store.profileIssues
            )

            if let profile = store.selectedProfile {
                PadGridView(
                    profile: profile,
                    padStates: store.padStates,
                    onPadTap: store.handlePadTap,
                    onPadPress: store.handlePadPress,
                    onPadRelease: store.handlePadRelease
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

struct ConnectionBarView: View {
    @ObservedObject var store: MappingStore
    @ObservedObject var midi: MidiManager
    @ObservedObject var osc: OscClient
    @State private var showingScanner = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connections")
                .font(.headline)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MIDI Output")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("MIDI Output", selection: $midi.selectedOutputId) {
                        if midi.outputs.isEmpty {
                            Text("No MIDI outputs")
                                .tag("")
                        } else {
                            ForEach(midi.outputs) { output in
                                Text(output.name)
                                    .tag(output.id)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(midi.outputs.isEmpty)
                }

                Button("Refresh MIDI") {
                    midi.refreshOutputs()
                }
                .disabled(midi.outputs.isEmpty)
            }

            HStack(spacing: 6) {
                Text("MIDI:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let selected = midi.outputs.first(where: { $0.id == midi.selectedOutputId }) {
                    Text("Selected: \(selected.name)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No output selected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OSC Host")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("192.168.1.10", text: $store.oscHost)
                        .oscHostInputModifiers()
                        .onSubmit {
                            Task {
                                await store.updateOscHost(store.oscHost.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                        }
                }

                Button("Scan QR") {
                    showingScanner = true
                }
                .buttonStyle(.bordered)

                Toggle(isOn: Binding(
                    get: { store.oscEnabled },
                    set: { enabled in
                        Task {
                            await store.setOscEnabled(enabled)
                        }
                    }
                )) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(oscStatusColor)
                            .frame(width: 10, height: 10)
                        Text("OSC Bridge")
                    }
                }
                .disabled(osc.state == .connecting)
            }

            if midi.outputs.isEmpty {
                Text("Connect a MIDI device.")
                    .foregroundStyle(.secondary)
            }

            if let error = store.oscHostError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
            if let hint = store.oscHostHint {
                Text(hint)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }

            if osc.state == .disconnected {
                HStack(spacing: 12) {
                    Text("OSC not connected")
                        .foregroundStyle(.secondary)
                    Button("Reconnect") {
                        Task {
                            await store.setOscEnabled(true)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.oscHostError != nil)
                }
            } else if osc.state == .connecting {
                Text("OSC connecting...")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text("OSC:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                switch osc.state {
                case .connected:
                    Text("Connected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .connecting:
                    Text("Connecting")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .disconnected:
                    Text("Disconnected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if osc.queuedCount > 0 {
                    Text("Queued: \(osc.queuedCount)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingScanner) {
            QRScannerView { code in
                showingScanner = false
                Task {
                    await store.updateOscHostFromQr(code)
                }
            } onCancel: {
                showingScanner = false
            }
        }
    }

    private var oscStatusColor: Color {
        switch osc.state {
        case .connected:
            return .green
        case .connecting:
            return .yellow
        case .disconnected:
            return .gray
        }
    }
}

struct LogPanelView: View {
    @ObservedObject var logs: LogStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Log")
                    .font(.headline)
                Spacer()
                Toggle("Debug", isOn: $logs.isEnabled)
                    .toggleStyle(.switch)
                Button("Clear") {
                    logs.clear()
                }
            }

            if logs.isEnabled {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(logs.entries) { entry in
                            Text("\(formatted(entry.timestamp))  \(entry.message)")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 140)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Debug logging disabled")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct ProfileBarView: View {
    let profiles: [Profile]
    let selectedId: String?
    let issues: [String: [String]]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(profiles) { profile in
                    Button {
                        onSelect(profile.id)
                    } label: {
                        HStack(spacing: 6) {
                            Text(profile.label ?? profile.id)
                                .font(.headline)
                            if let list = issues[profile.id], !list.isEmpty {
                                Text("!")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.yellow.opacity(0.9))
                                    .foregroundStyle(.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
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

struct ProfileIssuesView: View {
    let profileId: String?
    let issues: [String: [String]]

    @ViewBuilder var body: some View {
        if let profileId {
            let list = issues[profileId] ?? []
            if !list.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile warnings")
                        .font(.subheadline)
                    ForEach(list.prefix(3), id: \.self) { issue in
                        Text("- \(issue)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct PadGridView: View {
    let profile: Profile
    let padStates: [String: Bool]
    let onPadTap: (Pad) -> Void
    let onPadPress: (Pad) -> Void
    let onPadRelease: (Pad) -> Void

    var body: some View {
        let rows = max(profile.gridSize?.last ?? 8, 1)
        let cols = max(profile.gridSize?.first ?? 8, 1)
        let matrix = buildPadMatrix(pads: profile.pads, rows: rows, cols: cols)

        if profile.pads.isEmpty {
            Text("No pads in this profile.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<cols, id: \.self) { col in
                            if let pad = matrix[row][col] {
                                PadView(
                                    pad: pad,
                                    isOn: padStates[pad.id] ?? false,
                                    onTap: { onPadTap(pad) },
                                    onPress: { onPadPress(pad) },
                                    onRelease: { onPadRelease(pad) }
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
}

struct PadView: View {
    let pad: Pad
    let isOn: Bool
    let onTap: () -> Void
    let onPress: () -> Void
    let onRelease: () -> Void
    @State private var isPressed: Bool = false
    private let haptic = HapticFeedback()

    var body: some View {
        Text(pad.label ?? pad.id)
            .font(.headline)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(8)
            .background(isOn ? Color.green.opacity(0.9) : Color.gray.opacity(0.15))
            .foregroundStyle(isOn ? .black : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: isOn ? Color.green.opacity(0.2) : .clear, radius: 6)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .animation(.easeInOut(duration: 0.15), value: isOn)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture {
                if pad.toggle {
                    onTap()
                }
            }
            .pressEvents {
                isPressed = true
                haptic.impactOccurred()
                if !pad.toggle {
                    onPress()
                }
            } onRelease: {
                isPressed = false
                haptic.impactOccurred()
                if !pad.toggle {
                    onRelease()
                }
            }
    }
}

struct PressEventModifier: ViewModifier {
    let onPress: () -> Void
    let onRelease: () -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress() }
                    .onEnded { _ in onRelease() }
            )
    }
}

extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressEventModifier(onPress: onPress, onRelease: onRelease))
    }

    @ViewBuilder
    func oscHostInputModifiers() -> some View {
        #if canImport(UIKit)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .textContentType(.URL)
        #else
        self
        #endif
    }
}

func buildPadMatrix(pads: [Pad], rows: Int, cols: Int) -> [[Pad?]] {
    let safeRows = max(rows, 1)
    let safeCols = max(cols, 1)
    var matrix: [[Pad?]] = Array(repeating: Array(repeating: nil, count: safeCols), count: safeRows)

    for (index, pad) in pads.enumerated() {
        let defaultRow = index / safeCols
        let defaultCol = index % safeCols
        let row = pad.row ?? defaultRow
        let col = pad.col ?? defaultCol

        guard row >= 0, row < safeRows, col >= 0, col < safeCols else {
            continue
        }

        if matrix[row][col] == nil {
            matrix[row][col] = pad
        }
    }

    return matrix
}
