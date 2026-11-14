// LiveView.swift — the check as it runs, full screen if wanted.
//
// After Gemini's specification (docs/live-view.md), with its amendments:
// nothing moves that the check didn't do; no grades and no warning
// colours; no internal terms on screen; lean shown only once an axis has
// enough consistent answers; Author's Matrix screensaver as the Rain style.

import SwiftUI
import ModelCheck

enum LiveLook: String, CaseIterable, Identifiable {
    case manuscript, constellation, loom
    var id: String { rawValue }
    var title: String {
        switch self {
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

    @State private var look: LiveLook = .manuscript
    @State private var controlsShown = true
    @State private var lastMove = Date()
    @State private var inspected: Exchange?
    @State private var lastCycle = Date()
    @State private var lastModule: Item.Module?

    private var live: LiveState { app.live }
    private var dark: Bool {
        switch theme {
        case "paper": false
        case "obsidian": true
        default: systemScheme == .dark || look != .manuscript || manuscriptStyle == "rain"
        }
    }
    private var ink: Color { dark ? .white : Color(white: 0.08) }
    private var paper: Color { dark ? .black : Color(red: 0.98, green: 0.97, blue: 0.94) }

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()
            Group {
                switch look {
                case .manuscript:
                    if manuscriptStyle == "rain" {
                        RainView(live: live, privacy: privacy)
                    } else {
                        ManuscriptView(live: live, ink: ink, privacy: privacy) { inspected = $0 }
                    }
                case .constellation:
                    ConstellationView(live: live, bank: app.bank, ink: ink)
                case .loom:
                    LoomView(live: live, ink: ink)
                }
            }
            .transition(.opacity)

            if density != "ambient" { hud }
            if controlsShown { controls }
            if let profile = live.profile, !live.running {
                ProfileCardView(profile: profile, status: "checked") { _, _ in }
                    .frame(maxWidth: 640)
                    .padding(30)
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
        .onKeyPress { _ in showControls(); return .ignored }
        .onAppear { look = style == "random" ? .manuscript : (LiveLook(rawValue: style) ?? .manuscript) }
        .onChange(of: style) { _, new in if let l = LiveLook(rawValue: new) { look = l } }
        .task { await autoCycle() }
        .sheet(item: $inspected) { ExchangeDrawer(exchange: $0) }
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
                Picker("", selection: $look) {
                    ForEach(LiveLook.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 330)
                Toggle("Hide charged wording", isOn: $privacy).toggleStyle(.switch).controlSize(.small)
            }
            .padding(24)
        }
        .transition(.opacity)
    }

    // MARK: Behaviour

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
