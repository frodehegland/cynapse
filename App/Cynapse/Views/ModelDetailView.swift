// ModelDetailView.swift — one model: check it, and see what was found.

import SwiftUI
import ModelCheck

struct ModelDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    let entry: ModelEntry
    @State private var shown: StoredProfile?
    @State private var evidence: Evidence?

    var body: some View {
        // The card keeps the last full or quick Character Check; weekly
        // re-checks are listed in History. The Analysis Check has its own section.
        let all = (app.profiles[entry.id] ?? []).filter { $0.profile.run.kind != .analysis }
        // The chosen check as it now stands (a review may have been added since).
        let stored = shown.flatMap { s in all.first { $0.url == s.url } } ?? all.first { $0.profile.run.kind != .weekly } ?? all.first
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if app.runningEntry == entry.id { runningLine }
                if let judging = app.judging { Text(judging).foregroundStyle(.secondary) }
                if let problem = app.runProblem, app.selection == entry.id {
                    Text(problem).foregroundStyle(.secondary)
                }
                if let stored {
                    ProfileCardView(profile: stored.profile, status: app.status(of: entry)) { ids, title in
                        evidence = Evidence(title: title, ids: ids, stored: stored)
                    }
                } else if app.runningEntry != entry.id {
                    Text("No Character Check yet. A quick check takes a few minutes on a downloaded model; the full check runs for longer, and can be stopped and carried on.")
                        .foregroundStyle(.secondary)
                }
                analysisSection
                if let stored {
                    ProfileDetailView(stored: stored, entry: entry, history: all, shown: $shown) { ids, title in
                        evidence = Evidence(title: title, ids: ids, stored: stored)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .onChange(of: entry) { _, _ in shown = nil }
        // The questions behind a line, in a panel beside the profile.
        .inspector(isPresented: Binding(get: { evidence != nil }, set: { if !$0 { evidence = nil } })) {
            if let evidence {
                EvidenceView(evidence: evidence) { self.evidence = nil }
                    .id(evidence.id)
                    .inspectorColumnWidth(min: 360, ideal: 460, max: 700)
            }
        }
        .navigationTitle(entry.name)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.name).font(.largeTitle.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Text("Character Check").foregroundStyle(.secondary)
                Button("Quick") { app.startCheck(entry, mode: .quick); openLive() }
                    .keyboardShortcut("r")
                    .help("A quick Character Check: accuracy, candour, lean and consistency")
                Button("Full") { app.startCheck(entry, mode: .full); openLive() }
                    .help("The full Character Check, under every situation the questions list")
                Divider().frame(height: 16).padding(.horizontal, 6)
                Text("Analysis Check").foregroundStyle(.secondary)
                Button(app.latestAnalysis(entry) == nil ? "Run" : "Run Again") { app.startCheck(entry, mode: .analysis); openLive() }
                    .disabled(app.analysisBank == nil)
                    .help("Concepts, summaries and contrasts drawn from short passages; asked once per model")
                Spacer()
                Button("Live View") { openLive() }
                    .disabled(app.runningEntry == nil && app.live.profile == nil)
            }
            .disabled(app.bank == nil)
            .disabled(app.runningEntry != nil && app.runningEntry != entry.id)
        }
    }

    /// The Analysis Check: asked once, since a model's files don't change;
    /// shown as outdated if they (or macOS, for Apple's model) have.
    @ViewBuilder private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Analysis Check").font(.title3.weight(.semibold))
            if let analysis = app.latestAnalysis(entry) {
                ProfileCardView(profile: analysis.profile, status: app.analysisOutdated(entry) ? "changed" : "checked") { ids, title in
                    evidence = Evidence(title: title, ids: ids, stored: analysis)
                }
                ExternalReviewView(stored: analysis, entry: entry) { ids, title in
                    evidence = Evidence(title: title, ids: ids, stored: analysis)
                }
                .padding(.top, 6)
            } else if !(app.runningEntry == entry.id && app.live.mode == .analysis) {
                Text("Not run yet. The model is given nine short passages to draw concepts from, summarise, and compare. A model's files don't change, so this is asked once, not weekly.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        var parts = [entry.kindLabel]
        if case .local = entry.kind {
            if let fp = app.fingerprints[entry.id] {
                parts.append("fingerprint \(fp.hash.prefix(12))…  ·  \(ByteCountFormatter.string(fromByteCount: fp.size, countStyle: .file))")
            } else if app.fingerprinting.contains(entry.id) {
                parts.append("taking its fingerprint…")
            }
        }
        return parts.joined(separator: "  ·  ")
    }

    private var runningLine: some View {
        HStack(spacing: 12) {
            ProgressView(value: Double(app.live.done), total: Double(max(app.live.planned, 1)))
                .frame(maxWidth: 260)
            Text("Checking this model, \(app.live.done) of \(app.live.planned)")
                .monospacedDigit()
            Button("Stop") { app.stopCheck() }
        }
    }

    private func openLive() {
        openWindow(id: "live")
    }
}

struct Evidence: Identifiable {
    let id = UUID()
    let title: String
    let ids: [String]
    let stored: StoredProfile
}
