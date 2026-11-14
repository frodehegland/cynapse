// LiveView.swift — the check as it runs, full screen if wanted.
//
// After Gemini's specification (docs/live-view.md), with its amendments:
// nothing moves that the check didn't do; no grades and no warning
// colours; no internal terms on screen; lean shown only once an axis has
// enough consistent answers; Author's Matrix screensaver as the Rain style.

import SwiftUI
import ModelCheck

enum LiveLook: String, CaseIterable, Identifiable {
    case connections, manuscript, constellation, loom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .connections: "Connections"
        case .manuscript: "Manuscript"
        case .constellation: "Constellation"
        case .loom: "Loom"
        }
    }
}

enum LiveSettings {
    static let style = "LiveStyle"              // "random" or a LiveLook
    static let cycleSeconds = "LiveCycleSeconds" // 0 = at the end of each kind of question
    static let density = "LiveDensity"          // "ambient", "standard", "diagnostic"
    static let manuscriptStyle = "LiveManuscriptStyle" // "scroll" or "rain"
    static let privacy = "LivePrivacy"
    static let theme = "LiveTheme"              // "system", "paper", "obsidian"
    static let retro = "LiveRetro"
    static let retroPalette = "LiveRetroPalette" // "random" or a palette's name
    static let fullScreen = "LiveFullScreen"    // open in full screen
}

struct LiveView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage(LiveSettings.style) private var style = "random"
    @AppStorage(LiveSettings.cycleSeconds) private var cycleSeconds = 90
    @AppStorage(LiveSettings.density) private var density = "standard"
    @AppStorage(LiveSettings.manuscriptStyle) private var manuscriptStyle = "rain"
    @AppStorage(LiveSettings.privacy) private var privacy = false
    @AppStorage(LiveSettings.theme) private var theme = "system"
    @AppStorage(LiveSettings.retro) private var retro = false
    @AppStorage(LiveSettings.retroPalette) private var retroPaletteName = "random"
    @AppStorage(LiveSettings.fullScreen) private var openFullScreen = true

    @State private var look: LiveLook = .connections
    @State private var palette = RetroPalette.all.randomElement()!
    @State private var toggleFullScreen = false
    @State private var controlsShown = true
    @State private var lastMove = Date()
    @State private var inspected: Exchange?
    @State private var lastCycle = Date()
    @State private var lastModule: Item.Module?
    @State private var cardHidden = false
    @State private var evidence: Evidence?

    private var live: LiveState { app.live }
    /// The Retro palette in use, or nil when Retro is off.
    private var retroPalette: RetroPalette? { retro ? palette : nil }
    private var dark: Bool {
        // Glowing looks need the dark: on a light page their light vanishes.
        if retro || look == .connections || (look == .manuscript && manuscriptStyle == "rain") { return true }
        switch theme {
        case "paper": return false
        case "obsidian": return true
        default: return systemScheme == .dark || look != .manuscript || manuscriptStyle == "rain"
        }
    }
    private var ink: Color { retroPalette?.textColor ?? (dark ? .white : Color(white: 0.08)) }
    /// The words around the edges in the look's own colours: Retro's
    /// palette, the Rain's green, Synapses' blue, or the page's ink.
    private var edgeColor: Color {
        if let retroPalette { return retroPalette.textColor }
        switch look {
        case .connections: return Color(red: 0.62, green: 0.72, blue: 1.0)
        case .manuscript where manuscriptStyle == "rain": return Color(red: 0.35, green: 1.0, blue: 0.45)
        default: return ink
        }
    }
    private var paper: Color { dark ? .black : Color(red: 0.98, green: 0.97, blue: 0.94) }

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()
            Group {
                switch look {
                case .connections:
                    ConnectionsView(live: live, bank: app.bank, palette: retroPalette)
                case .manuscript:
                    if manuscriptStyle == "rain" {
                        RainView(live: live, privacy: privacy, palette: retroPalette)
                    } else {
                        ManuscriptView(live: live, ink: ink, privacy: privacy, palette: retroPalette) { inspected = $0 }
                    }
                case .constellation:
                    ConstellationView(live: live, bank: app.bank, ink: ink, line: retroPalette?.lineColor ?? ink)
                        .retroGlow(retroPalette)
                case .loom:
                    LoomView(live: live, ink: ink, line: retroPalette?.lineColor ?? ink)
                        .retroGlow(retroPalette)
                }
            }
            .transition(.opacity)

            FullScreenControl(request: $toggleFullScreen, fullScreenAtStart: openFullScreen).frame(width: 0, height: 0)
            if density != "ambient" { hud.retroGlow(retroPalette) }
            if controlsShown { controls }
            if let profile = live.profile, !live.running, !cardHidden {
                ProfileCardView(profile: profile, status: "checked") { ids, title in
                    // The stored check this profile came from, for its transcript.
                    if !ids.isEmpty, let stored = app.profiles.values.flatMap({ $0 }).first(where: { $0.profile.createdAt == profile.createdAt }) {
                        evidence = Evidence(title: title, ids: ids, stored: stored)
                    }
                }
                    .frame(maxWidth: 640)
                    .padding(30)
                    .overlay(alignment: .topTrailing) {
                        Button { withAnimation { cardHidden = true } } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).padding(10).help("Hide, to see the network behind")
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .foregroundStyle(ink)
        .environment(\.colorScheme, dark ? .dark : .light)
        .animation(.easeInOut(duration: 1.2), value: look)
        .animation(.easeInOut(duration: 1.5), value: live.profile == nil)
        .onContinuousHover { _ in showControls() }
        .onTapGesture { showControls() }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) { cycle(); return .handled }
        .onKeyPress(.escape) {
            if NSApp.keyWindow?.styleMask.contains(.fullScreen) == true { toggleFullScreen = true; return .handled }
            return .ignored
        }
        .onKeyPress { _ in showControls(); return .ignored }
        .onAppear {
            look = style == "random" ? .connections : (LiveLook(rawValue: style) ?? .connections)
            palette = RetroPalette.named(retroPaletteName)
            if !live.running && live.exchanges.isEmpty { app.replayLatest() }
        }
        .onChange(of: live.running) { _, running in if running { cardHidden = false } }
        .onChange(of: retroPaletteName) { _, new in palette = RetroPalette.named(new) }
        .onChange(of: style) { _, new in if let l = LiveLook(rawValue: new) { look = l } }
        .task { await autoCycle() }
        .sheet(item: $inspected) { ExchangeDrawer(exchange: $0) }
        .inspector(isPresented: Binding(get: { evidence != nil }, set: { if !$0 { evidence = nil } })) {
            if let evidence {
                EvidenceView(evidence: evidence) { self.evidence = nil }
                    .id(evidence.id)
                    .environment(\.colorScheme, .dark)
                    .inspectorColumnWidth(min: 360, ideal: 460, max: 700)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    // MARK: The three tiers

    private var hud: some View {
        VStack {
            HStack(alignment: .top) {
                identity
                Spacer()
                telemetry
            }
            Spacer()
            HStack(alignment: .bottom) {
                ticker
                Spacer()
            }
        }
        .padding(24)
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(edgeColor)
        .shadow(color: edgeColor.opacity(look == .connections || retro ? 0.6 : 0), radius: 4)
        .allowsHitTesting(false)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(live.model?.name ?? "No check running").font(.system(size: 14, weight: .semibold, design: .monospaced))
            Text([live.model?.quantisation, live.model?.runtime?.name, live.model.map { kindWord($0.provider) }].compactMap { $0 }.joined(separator: " · "))
            if let hash = live.model?.sha256 { Text("files pinned · sha256 \(hash.prefix(8))…\(hash.suffix(4))") }
            if let bank = live.bank { Text("questions \(bank.version) · signature verified") }
        }
        .opacity(0.75)
    }

    private var telemetry: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(live.done) of \(live.planned)").font(.system(size: 14, weight: .semibold, design: .monospaced))
            ForEach(Item.Module.allCases, id: \.self) { module in
                if let p = live.progress[module], p.total > 0 {
                    Text("\(moduleWord(module)) \(p.done)/\(p.total)")
                }
            }
            if let current = live.current, !current.situation.isEmpty { Text(current.situation).frame(maxWidth: 360, alignment: .trailing) }
            if let confirming = live.confirming { Text(confirming).frame(maxWidth: 360, alignment: .trailing) }
            if density == "diagnostic", let current = live.current {
                Text(current.key).opacity(0.6)
            }
        }
        .multilineTextAlignment(.trailing)
        .opacity(0.75)
    }

    private var ticker: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(live.ticker.suffix(density == "diagnostic" ? 8 : 3).enumerated()), id: \.offset) { index, line in
                Text(line).opacity(0.4 + 0.6 * Double(index + 1) / Double(min(live.ticker.count, 3) + 1))
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var controls: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                // Check the model shown here again, from the start.
                Button("Rescan") { rescan() }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .disabled(app.runningEntry != nil || rescanEntry == nil)
                    .help(rescanEntry.map { "Check \($0.name) again" } ?? "Choose a model to check")
                Picker("", selection: $look) {
                    ForEach(LiveLook.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 420)
                Toggle("Retro", isOn: $retro).toggleStyle(.switch).controlSize(.small)
                Toggle("Hide charged wording", isOn: $privacy).toggleStyle(.switch).controlSize(.small)
                Button { toggleFullScreen = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .help("Full screen (⌃⌘F)")
                    .keyboardShortcut("f", modifiers: [.control, .command])
            }
            .padding(24)
            .tint(edgeColor)
            .foregroundStyle(edgeColor)
        }
        .transition(.opacity)
    }

    // MARK: Behaviour

    /// The model this view is showing: the one being checked, else the one
    /// whose last check is shown, else the one chosen in the main window.
    private var rescanEntry: ModelEntry? {
        if let running = app.runningEntry { return app.entries.first { $0.id == running } }
        if let shown = live.profile,
           let entry = app.entries.first(where: { app.profiles[$0.id]?.contains { $0.profile.createdAt == shown.createdAt } == true }) {
            return entry
        }
        return app.selected
    }

    /// The same kind of check again (a weekly re-check is rescanned as a
    /// quick check), shown here as it runs.
    private func rescan() {
        guard let entry = rescanEntry else { return }
        let mode: RunMode = live.profile?.run.kind == .full ? .full : .quick
        cardHidden = false
        evidence = nil
        app.startCheck(entry, mode: mode)
    }

    private func showControls() {
        lastMove = Date()
        withAnimation { controlsShown = true }
    }

    private func cycle() {
        let all = LiveLook.allCases
        look = all[(all.firstIndex(of: look)! + 1) % all.count]
        lastCycle = Date()
    }

    private func autoCycle() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            // Controls fade after a few still seconds; moving pauses cycling.
            if controlsShown, Date().timeIntervalSince(lastMove) > 4 { withAnimation { controlsShown = false } }
            guard style == "random", Date().timeIntervalSince(lastMove) > 4, live.running else { continue }
            let module = live.current?.module
            let byTime = cycleSeconds > 0 && Date().timeIntervalSince(lastCycle) > Double(cycleSeconds)
            let byMilestone = cycleSeconds == 0 && module != nil && lastModule != nil && module != lastModule
            if byTime || byMilestone { cycle() }
            lastModule = module
        }
    }

    private func kindWord(_ provider: String) -> String {
        ["local": "on this Mac", "apple": "built into macOS", "cloud": "cloud", "stub": "stand-in"][provider] ?? provider
    }

    private func moduleWord(_ module: Item.Module) -> String {
        switch module {
        case .facts: "Facts"
        case .values: "Values"
        case .candour: "Candour"
        case .dialogue: "Conversations"
        case .work: "Work"
        }
    }
}

/// One exchange in full: the exact prompt, the settings, the raw answer.
struct ExchangeDrawer: View {
    @Environment(\.dismiss) private var dismiss
    let exchange: Exchange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(exchange.itemId).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if !exchange.situation.isEmpty { Text(exchange.situation).font(.callout).foregroundStyle(.secondary) }
            if let system = exchange.system { Text("System: \(system)").font(.caption.monospaced()) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(exchange.prompt).font(.system(.title3, design: .serif)).textSelection(.enabled)
                    Divider()
                    Text(exchange.answer).textSelection(.enabled)
                    if let plain = exchange.plain { Text(plain).font(.callout).foregroundStyle(.secondary) }
                }
            }
            Text("Temperature 0 · fixed seed where the model allows").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 640, height: 480)
    }
}
