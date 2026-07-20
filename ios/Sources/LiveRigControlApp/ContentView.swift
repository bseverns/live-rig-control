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

private enum AppTheme {
    static let background = Color(red: 0.051, green: 0.055, blue: 0.063)
    static let panel = Color(red: 0.082, green: 0.090, blue: 0.102)
    static let panelRaised = Color(red: 0.106, green: 0.118, blue: 0.133)
    static let line = Color.white.opacity(0.16)
    static let primaryText = Color(red: 0.957, green: 0.957, blue: 0.949)
    static let mutedText = Color(red: 0.659, green: 0.678, blue: 0.702)
    static let success = Color(red: 0.537, green: 0.820, blue: 0.561)
    static let warning = Color(red: 0.890, green: 0.749, blue: 0.380)
    static let danger = Color(red: 0.878, green: 0.435, blue: 0.435)
    static let panelRadius: CGFloat = 8
    static let controlRadius: CGFloat = 5
    static let padRadius: CGFloat = 6
}

private struct MinimalButtonStyle: ButtonStyle {
    enum Role {
        case normal
        case danger
    }

    @Environment(\.isEnabled) private var isEnabled

    var role: Role = .normal
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        let background = selectedBackground.opacity(configuration.isPressed ? 0.78 : 1)
        let foreground = selectedForeground
        let border = borderColor.opacity(isSelected ? 1 : 0.72)

        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(background)
            .foregroundStyle(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.55)
    }

    private var selectedBackground: Color {
        if isSelected {
            switch role {
            case .normal:
                return AppTheme.primaryText
            case .danger:
                return AppTheme.danger
            }
        }
        return AppTheme.panelRaised
    }

    private var selectedForeground: Color {
        if isSelected {
            return AppTheme.background
        }
        switch role {
        case .normal:
            return AppTheme.primaryText
        case .danger:
            return AppTheme.danger
        }
    }

    private var borderColor: Color {
        switch role {
        case .normal:
            return isSelected ? AppTheme.primaryText : AppTheme.line
        case .danger:
            return AppTheme.danger
        }
    }
}

struct ContentView: View {
    @StateObject private var store = MappingStore()
    @State private var showingConnections = false
    @State private var showingLogs = false
    @State private var selectedSection: PerformerSection?

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

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
                                .foregroundStyle(AppTheme.primaryText)
                            Spacer()
                            Text("\(profile.pads.count) controls")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.mutedText)
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
                        .foregroundStyle(AppTheme.mutedText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tint(AppTheme.primaryText)

            if store.isLoading {
                LoadingOverlayView()
            }
        }
        .task {
            await store.loadMappings()
        }
        .preferredColorScheme(.dark)
        .onChange(of: store.selectedProfileId) { _, _ in
            selectedSection = store.selectedProfile?.performerSection
        }
        .sheet(isPresented: $showingConnections) {
            NavigationStack {
                ScrollView {
                    ConnectionBarView(store: store, midi: store.midi, osc: store.osc)
                        .padding()
                }
                .background(AppTheme.background)
                .navigationTitle("Connections")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(AppTheme.panel, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
            }
            .presentationBackground(AppTheme.background)
        }
        .sheet(isPresented: $showingLogs) {
            NavigationStack {
                LogPanelView(logs: store.logs, maxHeight: nil)
                    .padding()
                    .navigationTitle("Log")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(AppTheme.panel, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
            }
            .background(AppTheme.background)
            .presentationBackground(AppTheme.background)
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

private enum PadRiskLevel: String {
    case low
    case medium
    case high
    case critical

    var label: String {
        switch self {
        case .low:
            return "LOW"
        case .medium:
            return "MED"
        case .high:
            return "HIGH"
        case .critical:
            return "CRIT"
        }
    }

    var color: Color {
        switch self {
        case .low:
            return AppTheme.success
        case .medium:
            return AppTheme.warning
        case .high:
            return AppTheme.warning
        case .critical:
            return AppTheme.danger
        }
    }

    var badgeFill: Color {
        switch self {
        case .low:
            return AppTheme.panel
        case .medium, .high:
            return AppTheme.warning
        case .critical:
            return AppTheme.danger
        }
    }

    var badgeForeground: Color {
        switch self {
        case .low:
            return AppTheme.primaryText
        case .medium, .high, .critical:
            return AppTheme.background
        }
    }
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
        switch layout?.kind {
        case "performanceDeck":
            return .performanceDeck
        case "parameterBoard":
            return .parameterBoard
        default:
            return .mappedGrid
        }
    }

    var minCardWidth: CGFloat {
        CGFloat(layout?.minCardWidth ?? 180)
    }
}

private extension Pad {
    var riskLevel: PadRiskLevel {
        PadRiskLevel(rawValue: risk ?? "") ?? .medium
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
            let columns = [
                GridItem(.adaptive(minimum: profile.minCardWidth, maximum: 240), spacing: 14)
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
    @State private var safeBlackoutArmed = false
    @State private var safeBlackoutArmId: UUID?
    let selectedProfileName: String?
    let onShowConnections: () -> Void
    let onShowLogs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Rig Control")
                        .font(.system(size: 32, weight: .bold, design: .default))
                        .foregroundStyle(AppTheme.primaryText)

                    if let selectedProfileName {
                        Text(selectedProfileName)
                            .font(.headline)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                }

                Spacer(minLength: 16)

                HStack(spacing: 10) {
                    StatusPill(
                        title: "MIDI",
                        detail: midi.isVirtualSourceActive ? midi.virtualSourceName : "Not Connected",
                        tint: midi.isVirtualSourceActive ? AppTheme.success : AppTheme.mutedText
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
                    .buttonStyle(MinimalButtonStyle())

                Button("Logs", action: onShowLogs)
                    .buttonStyle(MinimalButtonStyle())

                Button(safeBlackoutArmed ? "Confirm Blackout" : "Safe Blackout") {
                    handleSafeBlackout()
                }
                .buttonStyle(MinimalButtonStyle(role: .danger, isSelected: safeBlackoutArmed))

                Spacer()

                if store.oscEnabled || midi.isVirtualSourceActive || !midi.outputs.isEmpty {
                    Text("Control surface ready")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                } else {
                    Text("Set up MIDI or OSC, then select a profile.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
        }
        .padding(18)
        .background(AppTheme.panel)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
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
            return AppTheme.success
        case .connecting:
            return AppTheme.warning
        case .disconnected:
            return AppTheme.mutedText
        }
    }

    private func handleSafeBlackout() {
        if safeBlackoutArmed {
            safeBlackoutArmed = false
            safeBlackoutArmId = nil
            store.safeBlackout()
            return
        }

        let armId = UUID()
        safeBlackoutArmed = true
        safeBlackoutArmId = armId
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard safeBlackoutArmId == armId else { return }
            safeBlackoutArmed = false
            safeBlackoutArmId = nil
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
                    .foregroundStyle(AppTheme.mutedText)
            }

            Text(detail)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(AppTheme.panelRaised)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
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
                .foregroundStyle(AppTheme.primaryText)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MIDI Output")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedText)
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
                    .tint(AppTheme.primaryText)
                    .disabled(midi.outputs.isEmpty)
                }

                Button("Refresh MIDI") {
                    midi.refreshOutputs()
                }
                .buttonStyle(MinimalButtonStyle())
                .disabled(midi.outputs.isEmpty)
            }

            HStack(spacing: 6) {
                Text("MIDI:")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedText)
                if midi.isVirtualSourceActive {
                    Text("Source: \(midi.virtualSourceName)")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                }
                if let selected = midi.outputs.first(where: { $0.id == midi.selectedOutputId }) {
                    Text("Selected: \(selected.name)")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                } else {
                    Text("No output selected")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OSC Host")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedText)
                    TextField("192.168.1.10 or udp://192.168.1.10:9000", text: $store.oscHost)
                        .oscHostInputModifiers()
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(AppTheme.panelRaised)
                        .foregroundStyle(AppTheme.primaryText)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                                .stroke(AppTheme.line, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                        .onChange(of: store.oscHost) { host in
                            Task {
                                await store.updateOscHost(host, reconnect: false)
                            }
                        }
                        .onSubmit {
                            Task {
                                await store.updateOscHost(store.oscHost.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                        }
                }

                Button("Scan QR") {
                    showingScanner = true
                }
                .buttonStyle(MinimalButtonStyle())

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
                .foregroundStyle(AppTheme.primaryText)
                .tint(AppTheme.primaryText)
                .disabled(osc.state == .connecting)
            }

            if midi.outputs.isEmpty {
                Text(midi.isVirtualSourceActive ? "System MIDI source is active." : "Connect a MIDI device.")
                    .foregroundStyle(AppTheme.mutedText)
            }

            if let error = store.oscHostError {
                Text(error)
                    .foregroundStyle(AppTheme.danger)
                    .font(.footnote)
            }
            if let hint = store.oscHostHint {
                Text(hint)
                    .foregroundStyle(AppTheme.mutedText)
                    .font(.footnote)
            }

            if osc.state == .disconnected {
                HStack(spacing: 12) {
                    Text("OSC not connected")
                        .foregroundStyle(AppTheme.mutedText)
                    Button("Reconnect") {
                        Task {
                            await store.setOscEnabled(true)
                        }
                    }
                    .buttonStyle(MinimalButtonStyle())
                    .disabled(store.oscHostError != nil)
                }
            } else if osc.state == .connecting {
                Text("OSC connecting...")
                    .foregroundStyle(AppTheme.mutedText)
            }

            HStack(spacing: 6) {
                Text("OSC:")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedText)
                switch osc.state {
                case .connected:
                    Text("Connected")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                case .connecting:
                    Text("Connecting")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                case .disconnected:
                    Text("Disconnected")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                }
                if osc.queuedCount > 0 {
                    Text("Queued: \(osc.queuedCount)")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
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
            return AppTheme.success
        case .connecting:
            return AppTheme.warning
        case .disconnected:
            return AppTheme.mutedText
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
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Toggle("Debug", isOn: $logs.isEnabled)
                    .toggleStyle(.switch)
                    .tint(AppTheme.primaryText)
                Button("Clear") {
                    logs.clear()
                }
                .buttonStyle(MinimalButtonStyle())
            }

            if logs.isEnabled {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(logs.entries) { entry in
                            Text("\(formatted(entry.timestamp))  \(entry.message)")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(AppTheme.mutedText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: maxHeight)
                .background(AppTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.padRadius, style: .continuous)
                        .stroke(AppTheme.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.padRadius, style: .continuous))
            } else {
                Text("Debug logging disabled")
                    .foregroundStyle(AppTheme.mutedText)
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
                        .background(selectedSection == section ? AppTheme.primaryText : AppTheme.panelRaised)
                        .foregroundStyle(selectedSection == section ? AppTheme.background : AppTheme.primaryText)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                                .stroke(selectedSection == section ? AppTheme.primaryText : AppTheme.line, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
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
                                        .background(AppTheme.warning)
                                        .foregroundStyle(AppTheme.background)
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(profile.id == selectedId ? AppTheme.primaryText : AppTheme.panelRaised)
                            .foregroundStyle(profile.id == selectedId ? AppTheme.background : AppTheme.primaryText)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                                    .stroke(profile.id == selectedId ? AppTheme.primaryText : AppTheme.line, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
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
                        .foregroundStyle(AppTheme.primaryText)
                    ForEach(list.prefix(3), id: \.self) { issue in
                        Text("- \(issue)")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedText)
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
                .foregroundStyle(AppTheme.mutedText)
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
        ZStack(alignment: .topTrailing) {
            Text(pad.label ?? pad.id)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 18)
                .foregroundStyle(isOn ? AppTheme.background : AppTheme.primaryText)

            Text(pad.riskLevel.label)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(pad.riskLevel.badgeFill)
                .foregroundStyle(pad.riskLevel.badgeForeground)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(AppTheme.line, lineWidth: pad.riskLevel == .low ? 1 : 0)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(6)
        }
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(8)
            .background(isOn ? AppTheme.success : AppTheme.panelRaised)
            .foregroundStyle(isOn ? AppTheme.background : AppTheme.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.padRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.padRadius, style: .continuous)
                    .stroke(isOn ? AppTheme.success : pad.riskLevel.color.opacity(pad.riskLevel == .critical ? 1 : 0.58), lineWidth: pad.riskLevel == .critical ? 2 : 1)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .animation(.easeInOut(duration: 0.15), value: isOn)
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.padRadius, style: .continuous))
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
            HStack(alignment: .firstTextBaseline) {
                Text(pad.label ?? pad.id)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(2)
                Spacer()
                Text(pad.riskLevel.label)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(pad.riskLevel.badgeFill)
                    .foregroundStyle(pad.riskLevel.badgeForeground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(AppTheme.line, lineWidth: pad.riskLevel == .low ? 1 : 0)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Slider(
                value: $localValue,
                in: minValue...maxValue,
                step: stepValue
            )
            .controlSize(.large)
            .tint(AppTheme.primaryText)
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
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding(8)
        .background(AppTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.padRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.padRadius, style: .continuous)
                .stroke(pad.riskLevel.color.opacity(pad.riskLevel == .critical ? 1 : 0.58), lineWidth: pad.riskLevel == .critical ? 2 : 1)
        )
        .onAppear {
            localValue = Double(value)
        }
    }
}

struct LoadingOverlayView: View {
    var body: some View {
        ZStack {
            AppTheme.background.opacity(0.72)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppTheme.primaryText)
                Text("Loading mappings…")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
            }
            .padding(20)
            .background(AppTheme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
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
