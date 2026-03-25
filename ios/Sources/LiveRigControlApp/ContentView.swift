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
    @State private var showingConnections = false
    @State private var showingLogs = false
    @State private var selectedSection: PerformerSection?

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                HeaderPanelView(
                    store: store,
                    midi: store.midi,
                    osc: store.osc,
                    selectedProfileName: store.selectedProfile?.label ?? store.selectedProfile?.id,
                    onShowConnections: { showingConnections = true },
                    onShowLogs: { showingLogs = true }
                )

                SectionBarView(
                    sections: availableSections,
                    selectedSection: currentSection,
                    onSelect: selectSection
                )

                ProfileBarView(
                    profiles: profilesInCurrentSection,
                    selectedId: store.selectedProfileId,
                    issues: store.profileIssues,
                    onSelect: store.selectProfile
                )

                ProfileIssuesView(
                    profileId: store.selectedProfileId,
                    issues: store.profileIssues
                )

                if let profile = store.selectedProfile {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(profile.label ?? profile.id)
                                .font(.title3)
                                .bold()
                            Spacer()
                            Text("\(profile.pads.count) controls")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        ProfileSurfaceView(
                            profile: profile,
                            padStates: store.padStates,
                            sliderValue: store.sliderValue,
                            onSliderChange: store.handleSliderChange,
                            onPadTap: store.handlePadTap,
                            onPadPress: store.handlePadPress,
                            onPadRelease: store.handlePadRelease
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Text("No profile loaded")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if store.isLoading {
                LoadingOverlayView()
            }
        }
        .task {
            await store.loadMappings()
        }
        .onChange(of: store.selectedProfileId) { _, _ in
            selectedSection = store.selectedProfile?.performerSection
        }
        .sheet(isPresented: $showingConnections) {
            NavigationStack {
                ScrollView {
                    ConnectionBarView(store: store, midi: store.midi, osc: store.osc)
                        .padding()
                }
                .navigationTitle("Connections")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showingLogs) {
            NavigationStack {
                LogPanelView(logs: store.logs, maxHeight: nil)
                    .padding()
                    .navigationTitle("Log")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var availableSections: [PerformerSection] {
        let sectionSet = Set(store.profiles.map(\.performerSection))
        return PerformerSection.allCases.filter(sectionSet.contains)
    }

    private var currentSection: PerformerSection {
        if let selectedSection, availableSections.contains(selectedSection) {
            return selectedSection
        }
        if let selected = store.selectedProfile {
            return selected.performerSection
        }
        return availableSections.first ?? .show
    }

    private var profilesInCurrentSection: [Profile] {
        store.profiles.filter { $0.performerSection == currentSection }
    }

    private func selectSection(_ section: PerformerSection) {
        selectedSection = section
        guard let first = store.profiles.first(where: { $0.performerSection == section }) else {
            return
        }
        if store.selectedProfile?.performerSection != section {
            store.selectProfile(first.id)
        }
    }
}

private enum ProfileLayoutKind {
    case performanceDeck
    case parameterBoard
    case mappedGrid
}

private extension Profile {
    var sortedPadsForDisplay: [Pad] {
        pads.sorted {
            let lhsRow = $0.row ?? .max
            let rhsRow = $1.row ?? .max
            if lhsRow != rhsRow { return lhsRow < rhsRow }

            let lhsCol = $0.col ?? .max
            let rhsCol = $1.col ?? .max
            if lhsCol != rhsCol { return lhsCol < rhsCol }

            return $0.id < $1.id
        }
    }

    var layoutKind: ProfileLayoutKind {
        switch id {
        case "transport", "patterns":
            return .performanceDeck
        case "msvp", "seedbox", "pcm30Macros", "drumStack", "electribe", "mn42Slots":
            return .parameterBoard
        default:
            return .mappedGrid
        }
    }
}

struct ProfileSurfaceView: View {
    let profile: Profile
    let padStates: [String: Bool]
    let sliderValue: (Pad) -> Int
    let onSliderChange: (Pad, Int) -> Void
    let onPadTap: (Pad) -> Void
    let onPadPress: (Pad) -> Void
    let onPadRelease: (Pad) -> Void

    var body: some View {
        switch profile.layoutKind {
        case .performanceDeck:
            PerformanceDeckView(
                profile: profile,
                padStates: padStates,
                onPadTap: onPadTap,
                onPadPress: onPadPress,
                onPadRelease: onPadRelease
            )
        case .parameterBoard:
            ParameterBoardView(
                profile: profile,
                padStates: padStates,
                sliderValue: sliderValue,
                onSliderChange: onSliderChange,
                onPadTap: onPadTap,
                onPadPress: onPadPress,
                onPadRelease: onPadRelease
            )
        case .mappedGrid:
            PadGridContainer(
                profile: profile,
                padStates: padStates,
                sliderValue: sliderValue,
                onSliderChange: onSliderChange,
                onPadTap: onPadTap,
                onPadPress: onPadPress,
                onPadRelease: onPadRelease
            )
        }
    }
}

struct PerformanceDeckView: View {
    let profile: Profile
    let padStates: [String: Bool]
    let onPadTap: (Pad) -> Void
    let onPadPress: (Pad) -> Void
    let onPadRelease: (Pad) -> Void

    var body: some View {
        GeometryReader { proxy in
            let pads = profile.sortedPadsForDisplay
            let columns = min(max(pads.count, 1), 4)
            let spacing: CGFloat = 16
            let availableWidth = max(proxy.size.width, 320)
            let rawWidth = (availableWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let cardWidth = min(max(rawWidth, 180), 260)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(pads) { pad in
                        PadView(
                            pad: pad,
                            isOn: padStates[pad.id] ?? false,
                            onTap: { onPadTap(pad) },
                            onPress: { onPadPress(pad) },
                            onRelease: { onPadRelease(pad) },
                            minHeight: 190
                        )
                        .frame(width: cardWidth)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
                .padding(.vertical, 8)
            }
        }
    }
}

struct ParameterBoardView: View {
    let profile: Profile
    let padStates: [String: Bool]
    let sliderValue: (Pad) -> Int
    let onSliderChange: (Pad, Int) -> Void
    let onPadTap: (Pad) -> Void
    let onPadPress: (Pad) -> Void
    let onPadRelease: (Pad) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 320)
            let minCardWidth: CGFloat = profile.id == "mn42Slots" ? 120 : 180
            let columns = [
                GridItem(.adaptive(minimum: minCardWidth, maximum: 240), spacing: 14)
            ]

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(profile.sortedPadsForDisplay) { pad in
                        if pad.ui?.type == "slider" {
                            PadSliderView(
                                pad: pad,
                                value: sliderValue(pad),
                                onChange: { onSliderChange(pad, $0) },
                                minHeight: width > 900 ? 150 : 170
                            )
                        } else {
                            PadView(
                                pad: pad,
                                isOn: padStates[pad.id] ?? false,
                                onTap: { onPadTap(pad) },
                                onPress: { onPadPress(pad) },
                                onRelease: { onPadRelease(pad) },
                                minHeight: 150
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

struct HeaderPanelView: View {
    @ObservedObject var store: MappingStore
    @ObservedObject var midi: MidiManager
    @ObservedObject var osc: OscClient
    let selectedProfileName: String?
    let onShowConnections: () -> Void
    let onShowLogs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Rig Control")
                        .font(.system(size: 32, weight: .bold, design: .rounded))

                    if let selectedProfileName {
                        Text(selectedProfileName)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 16)

                HStack(spacing: 10) {
                    StatusPill(
                        title: "MIDI",
                        detail: midi.outputs.first(where: { $0.id == midi.selectedOutputId })?.name ?? "Not Connected",
                        tint: midi.outputs.isEmpty ? .gray : .green
                    )
                    StatusPill(
                        title: "OSC",
                        detail: oscLabel,
                        tint: oscTint
                    )
                }
            }

            HStack(spacing: 10) {
                Button("Connections", action: onShowConnections)
                    .buttonStyle(.borderedProminent)

                Button("Logs", action: onShowLogs)
                    .buttonStyle(.bordered)

                Spacer()

                if store.oscEnabled || !midi.outputs.isEmpty {
                    Text("Control surface ready")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Set up MIDI or OSC, then select a profile.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var oscLabel: String {
        switch osc.state {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return "Disconnected"
        }
    }

    private var oscTint: Color {
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

struct StatusPill: View {
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(detail)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
                    TextField("192.168.1.10 or udp://192.168.1.10:9000", text: $store.oscHost)
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
            QRScannerView(
                onScan: { code in
                    showingScanner = false
                    Task {
                        await store.updateOscHostFromQr(code)
                    }
                },
                onCancel: {
                    showingScanner = false
                }
            )
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
    let maxHeight: CGFloat?

    init(logs: LogStore, maxHeight: CGFloat? = 140) {
        self.logs = logs
        self.maxHeight = maxHeight
    }

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
                .frame(maxHeight: maxHeight)
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

struct SectionBarView: View {
    let sections: [PerformerSection]
    let selectedSection: PerformerSection
    let onSelect: (PerformerSection) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(sections) { section in
                Button {
                    onSelect(section)
                } label: {
                    Text(section.title)
                        .font(.headline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background(selectedSection == section ? Color.primary : Color.gray.opacity(0.12))
                        .foregroundStyle(selectedSection == section ? .white : .primary)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

struct ProfileBarView: View {
    let profiles: [Profile]
    let selectedId: String?
    let issues: [String: [String]]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(profiles) { profile in
                        Button {
                            onSelect(profile.id)
                        } label: {
                            HStack(spacing: 6) {
                                Text(profile.label ?? profile.id)
                                    .font(.headline)
                                    .lineLimit(1)
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
                            .background(profile.id == selectedId ? .blue : .gray.opacity(0.14))
                            .foregroundStyle(profile.id == selectedId ? .white : .primary)
                            .clipShape(Capsule())
                        }
                        .id(profile.id)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onAppear {
                guard let selectedId else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(selectedId, anchor: .center)
                }
            }
            .onChange(of: selectedId) { _, next in
                guard let next else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(next, anchor: .center)
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

struct PadGridContainer: View {
    let profile: Profile
    let padStates: [String: Bool]
    let sliderValue: (Pad) -> Int
    let onSliderChange: (Pad, Int) -> Void
    let onPadTap: (Pad) -> Void
    let onPadPress: (Pad) -> Void
    let onPadRelease: (Pad) -> Void

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 10
            let cols = max(profile.gridSize?.first ?? 8, 1)
            let targetCols = min(cols, 8)
            let availableWidth = max(proxy.size.width, 320)
            let computed = (availableWidth - spacing * CGFloat(targetCols - 1)) / CGFloat(targetCols)
            let cellSize = max(88, floor(computed))
            let gridWidth = max(availableWidth, CGFloat(cols) * cellSize + spacing * CGFloat(cols - 1))
            let sliderHeight = max(104, cellSize * 1.15)

            ScrollView([.vertical, .horizontal]) {
                PadGridView(
                    profile: profile,
                    padStates: padStates,
                    sliderValue: sliderValue,
                    onSliderChange: onSliderChange,
                    onPadTap: onPadTap,
                    onPadPress: onPadPress,
                    onPadRelease: onPadRelease,
                    cellSize: cellSize,
                    sliderHeight: sliderHeight,
                    spacing: spacing
                )
                .frame(width: gridWidth, alignment: .leading)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.visible)
        }
    }
}

struct PadGridView: View {
    let profile: Profile
    let padStates: [String: Bool]
    let sliderValue: (Pad) -> Int
    let onSliderChange: (Pad, Int) -> Void
    let onPadTap: (Pad) -> Void
    let onPadPress: (Pad) -> Void
    let onPadRelease: (Pad) -> Void
    let cellSize: CGFloat
    let sliderHeight: CGFloat
    let spacing: CGFloat

    var body: some View {
        let rows = max(profile.gridSize?.last ?? 8, 1)
        let cols = max(profile.gridSize?.first ?? 8, 1)
        let matrix = buildPadMatrix(pads: profile.pads, rows: rows, cols: cols)

        if profile.pads.isEmpty {
            Text("No pads in this profile.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<cols, id: \.self) { col in
                            if let pad = matrix[row][col] {
                                if pad.ui?.type == "slider" {
                                    PadSliderView(
                                        pad: pad,
                                        value: sliderValue(pad),
                                        onChange: { onSliderChange(pad, $0) },
                                        minHeight: sliderHeight
                                    )
                                    .frame(width: cellSize)
                                } else {
                                    PadView(
                                        pad: pad,
                                        isOn: padStates[pad.id] ?? false,
                                        onTap: { onPadTap(pad) },
                                        onPress: { onPadPress(pad) },
                                        onRelease: { onPadRelease(pad) },
                                        minHeight: cellSize
                                    )
                                    .frame(width: cellSize)
                                }
                            } else {
                                Color.clear
                                    .frame(width: cellSize, height: cellSize)
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
    let minHeight: CGFloat
    @State private var isPressed: Bool = false
    private let haptic = HapticFeedback()

    var body: some View {
        Text(pad.label ?? pad.id)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity, minHeight: minHeight)
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
                if pad.isToggle {
                    onTap()
                }
            }
            .pressEvents {
                isPressed = true
                haptic.impactOccurred()
                if !pad.isToggle {
                    onPress()
                }
            } onRelease: {
                isPressed = false
                haptic.impactOccurred()
                if !pad.isToggle {
                    onRelease()
                }
            }
    }
}

struct PadSliderView: View {
    let pad: Pad
    let value: Int
    let onChange: (Int) -> Void
    let minHeight: CGFloat
    @State private var localValue: Double = 0

    private var minValue: Double { Double(pad.ui?.min ?? 0) }
    private var maxValue: Double { Double(pad.ui?.max ?? 127) }
    private var stepValue: Double { Double(pad.ui?.step ?? 1) }
    private var showValue: Bool { pad.ui?.showValue ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pad.label ?? pad.id)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Slider(
                value: $localValue,
                in: minValue...maxValue,
                step: stepValue
            )
            .controlSize(.large)
            .onChange(of: localValue) { _, newValue in
                let intValue = Int(newValue.rounded())
                if intValue != value {
                    onChange(intValue)
                }
            }
            .onChange(of: value) { _, newValue in
                let next = Double(newValue)
                if abs(next - localValue) > 0.001 {
                    localValue = next
                }
            }
            if showValue {
                Text("\(value)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding(8)
        .background(Color.gray.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            localValue = Double(value)
        }
    }
}

struct LoadingOverlayView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                Text("Loading mappings…")
                    .font(.headline)
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .transition(.opacity)
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
    var matrix: [[Pad?]] = Array(
        repeating: Array<Pad?>(repeating: nil, count: safeCols),
        count: safeRows
    )

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
