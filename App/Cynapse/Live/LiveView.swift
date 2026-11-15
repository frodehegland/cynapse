// LiveView.swift — the check as it runs, full screen if wanted, drawn as
// Connections (ConnectionsView.swift), the one look.
//
// After Gemini's specification (docs/live-view.md), with its amendments:
// nothing moves that the check didn't do; no grades and no warning
// colours; no internal terms on screen; lean shown only once an axis has
// enough consistent answers.

import SwiftUI
import ModelCheck

enum LiveSettings {
    static let density = "LiveDensity"          // "ambient", "standard", "diagnostic"
    static let privacy = "LivePrivacy"
    static let retro = "LiveRetro"
    static let retroPalette = "LiveRetroPalette" // "random" or a palette's name
    static let fullScreen = "LiveFullScreen"    // open in full screen
}

struct LiveView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(LiveSettings.density) private var density = "standard"
    @AppStorage(LiveSettings.privacy) private var privacy = false
    @AppStorage(LiveSettings.retro) private var retro = false
    @AppStorage(LiveSettings.retroPalette) private var retroPaletteName = "random"
    @AppStorage(LiveSettings.fullScreen) private var openFullScreen = true

    @State private var palette = RetroPalette.all.randomElement()!
    @State private var toggleFullScreen = false
    @State private var controlsShown = true
    @State private var lastMove = Date()
    @State private var cardHidden = false
    @State private var evidence: Evidence?
    /// A dot clicked in Connections, shown in the panel.
    @State private var picked: ConnectionPick?

    private var live: LiveState { app.live }
    /// The Retro palette in use, or nil when Retro is off.
    private var retroPalette: RetroPalette? { retro ? palette : nil }
    private var ink: Color { retroPalette?.textColor ?? .white }
    /// The words around the edges: Retro's palette, or a deeper, quieter
    /// blue than the network's, so the words sit back and the connections
    /// stand out.
    private var edgeColor: Color { retroPalette?.textColor ?? Color(red: 0.36, green: 0.44, blue: 0.70) }

    var body: some View {
        ZStack {
            // The network glows: it needs the dark.
            Color.black.ignoresSafeArea()
            ConnectionsView(live: live, bank: app.liveBank ?? app.bank, palette: retroPalette, picked: picked) { pick in
                evidence = nil
                picked = pick
            }

            FullScreenControl(request: $toggleFullScreen, fullScreenAtStart: openFullScreen).frame(width: 0, height: 0)
            if density != "ambient" { hud.retroGlow(retroPalette) }
            if controlsShown { controls }
            if let profile = live.profile, !live.running, !cardHidden {
                // Clicking anywhere outside the report puts it away.
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { hideCard() }
                    .transition(.opacity)
                ProfileCardView(profile: profile, status: "checked", close: { hideCard() }) { ids, title in
                    // The stored check this profile came from, for its transcript.
                    if !ids.isEmpty, let stored = app.profiles.values.flatMap({ $0 }).first(where: { $0.profile.createdAt == profile.createdAt }) {
                        picked = nil
                        evidence = Evidence(title: title, ids: ids, stored: stored)
                    }
                }
                    .frame(maxWidth: 640)
                    .padding(30)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .foregroundStyle(ink)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 1.5), value: live.profile == nil)
        .onContinuousHover { _ in showControls() }
        .onTapGesture { showControls() }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            if live.profile != nil, !live.running, !cardHidden { hideCard(); return .handled }
            if NSApp.keyWindow?.styleMask.contains(.fullScreen) == true { toggleFullScreen = true; return .handled }
            return .ignored
        }
        .onKeyPress { _ in showControls(); return .ignored }
        .onAppear {
            palette = RetroPalette.named(retroPaletteName)
            if !live.running && live.exchanges.isEmpty { app.replayLatest() }
        }
        .onChange(of: live.running) { _, running in if running { cardHidden = false } }
        .onChange(of: retroPaletteName) { _, new in palette = RetroPalette.named(new) }
        .task { await fadeControls() }
        .inspector(isPresented: Binding(get: { evidence != nil || picked != nil },
                                        set: { if !$0 { evidence = nil; picked = nil } })) {
            Group {
                if let picked {
                    ConnectionPanel(pick: picked, live: live, bank: app.liveBank ?? app.bank, privacy: privacy) { self.picked = nil }
                        .id(picked.id)
                } else if let evidence {
                    EvidenceView(evidence: evidence) { self.evidence = nil }
                        .id(evidence.id)
                }
            }
            .environment(\.colorScheme, .dark)
            .inspectorColumnWidth(min: 360, ideal: 460, max: 700)
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
        .shadow(color: edgeColor.opacity(retro ? 0.6 : 0), radius: 4)
        .allowsHitTesting(false)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(live.model?.name ?? "No check running").font(.system(size: 14, weight: .semibold, design: .monospaced))
            Text([live.model?.quantisation, live.model?.runtime?.name, live.model.map { kindWord($0.provider) }].compactMap { $0 }.joined(separator: " · "))
            if let hash = live.model?.sha256 { Text("files pinned · sha256 \(hash.prefix(8))…\(hash.suffix(4))") }
            if let bank = live.bank { Text("questions \(bank.version) · " + (live.bankVerified ? "signature verified" : "draft, not yet signed")) }
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
            // A check that stopped says why here too, not only in the main window.
            if let problem = app.runProblem {
                Text(problem).foregroundStyle(Assessment.wrong.color).frame(maxWidth: 360, alignment: .trailing)
            }
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
                // The report again, once it has been put away.
                if live.profile != nil, !live.running, cardHidden {
                    Button("Report") { withAnimation { cardHidden = false } }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .help("Show the report of this check again")
                }
                // Check the model shown here again, from the start.
                Button("Rescan") { rescan() }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .disabled(app.runningEntry != nil || rescanEntry == nil)
                    .help(rescanEntry.map { "Check \($0.name) again" } ?? "Choose a model to check")
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
        let kind = live.profile?.run.kind ?? live.mode
        let mode: RunMode = kind == .full || kind == .analysis ? kind : .quick
        cardHidden = false
        evidence = nil
        picked = nil
        app.startCheck(entry, mode: mode)
    }

    private func hideCard() {
        withAnimation { cardHidden = true }
        showControls()
    }

    private func showControls() {
        lastMove = Date()
        withAnimation { controlsShown = true }
    }

    /// The controls fade after a few still seconds.
    private func fadeControls() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            if controlsShown, Date().timeIntervalSince(lastMove) > 4 { withAnimation { controlsShown = false } }
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
        case .analysis: "Analysis"
        }
    }
}
