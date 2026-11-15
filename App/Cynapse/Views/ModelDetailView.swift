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
                // What can be done first; what was found, below it.
                checkPanel(lastCharacter: all.first { $0.profile.run.kind != .weekly })
                if app.runningEntry == entry.id { runningLine }
                if let judging = app.judging { Text(judging).foregroundStyle(.secondary) }
                if let problem = app.runProblem, app.selection == entry.id {
                    Text(problem).foregroundStyle(.secondary)
                }
                if stored != nil || app.latestAnalysis(entry) != nil {
                    Text("Results").font(.title2.weight(.semibold)).padding(.top, 8)
                }
                // First of all: anything that changed since the check before
                // of the same kind, or that nothing did.
                if let stored, let before = previous(of: stored, in: all) {
                    ChangesView(current: stored, previous: before) { ids, title in
                        evidence = Evidence(title: title, ids: ids, stored: stored)
                    }
                }
                if let analysis = app.latestAnalysis(entry),
                   let before = previous(of: analysis, in: (app.profiles[entry.id] ?? []).filter { $0.profile.run.kind == .analysis }) {
                    ChangesView(current: analysis, previous: before) { ids, title in
                        evidence = Evidence(title: title, ids: ids, stored: analysis)
                    }
                }
                if let stored {
                    ProfileCardView(profile: stored.profile, status: app.status(of: entry)) { ids, title in
                        evidence = Evidence(title: title, ids: ids, stored: stored)
                    }
                }
                analysisSection
                if let stored {
                    ProfileDetailView(stored: stored, entry: entry, history: all, shown: $shown) { ids, title in
                        evidence = Evidence(title: title, ids: ids, stored: stored)
                    }
                }
                // At the bottom of the report: all of it, as one document.
                if stored != nil || app.latestAnalysis(entry) != nil {
                    Divider().padding(.top, 8)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Button("Export Full Report as Markdown…", systemImage: "square.and.arrow.up") {
                            app.exportReport(entry, character: stored)
                        }
                        .controlSize(.large)
                        Text("Every result, what changed since the check before, the external reviews, and every question with the model's exact answer, in one Markdown file.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
        // Always opens at the top, on the ways to check the model; a new
        // model starts afresh rather than where the last was scrolled to.
        .defaultScrollAnchor(.top)
        .id(entry.id)
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
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.name).font(.largeTitle.weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            Button("Live View") { openLive() }
                .disabled(app.runningEntry == nil && app.live.profile == nil)
        }
    }

    /// The two checks, side by side, each with what it does and when it last ran.
    private func checkPanel(lastCharacter: StoredProfile?) -> some View {
        let analysis = app.latestAnalysis(entry)
        return HStack(alignment: .top, spacing: 14) {
            checkBox(title: "Character Check",
                     what: "Whether it is right, makes things up, gives way to pressure, where it leans, and whether its answers change with the date or who is asking.",
                     last: lastCharacter.map { "Last checked " + when($0) } ?? "Not checked yet. Quick takes a few minutes on a downloaded model; Full runs longer, and can be stopped and carried on.") {
                Button("Quick Check") { app.startCheck(entry, mode: .quick); openLive() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("r")
                    .help("Every question in its first wording, and the weekly questions in a few situations (⌘R)")
                Button("Full Check") { app.startCheck(entry, mode: .full); openLive() }
                    .help("Every wording, every situation, and the conversations under pressure")
            }
            checkBox(title: "Analysis Check",
                     what: "How it draws concepts from a passage, summarises a disagreement fairly, and names where two passages part.",
                     last: analysis.map { (app.analysisOutdated(entry) ? "Out of date: the model has changed since " : "Run ") + when($0) + ". Asked once; not repeated weekly." }
                        ?? "Not run yet. Nine short passages; asked once per model.") {
                Button(analysis == nil ? "Run Analysis Check" : "Run Again") { app.startCheck(entry, mode: .analysis); openLive() }
                    .buttonStyle(.borderedProminent)
                    .disabled(app.analysisBank == nil)
                    .help("Concepts, summaries and contrasts drawn from nine short passages")
            }
        }
        .controlSize(.large)
        .disabled(app.bank == nil)
        .disabled(app.runningEntry != nil)
    }

    private func checkBox<Buttons: View>(title: String, what: String, last: String, @ViewBuilder buttons: () -> Buttons) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            Text(what).fixedSize(horizontal: false, vertical: true)
            HStack { buttons() }
            Text(last).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }

    /// The check of the same kind just before this one (quick with quick,
    /// full with full, Analysis with Analysis); nil if there is none.
    private func previous(of stored: StoredProfile, in checks: [StoredProfile]) -> StoredProfile? {
        checks.filter { $0.profile.run.kind == stored.profile.run.kind && $0.date < stored.date }
            .max { $0.date < $1.date }
    }

    private func when(_ stored: StoredProfile) -> String {
        stored.date.formatted(date: .abbreviated, time: .shortened)
    }

    /// The Analysis Check: asked once, since a model's files don't change;
    /// shown as outdated if they (or macOS, for Apple's model) have.
    @ViewBuilder private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let analysis = app.latestAnalysis(entry) {
                Text("Analysis Check").font(.title3.weight(.semibold))
                ProfileCardView(profile: analysis.profile, status: app.analysisOutdated(entry) ? "changed" : "checked") { ids, title in
                    evidence = Evidence(title: title, ids: ids, stored: analysis)
                }
                ExternalReviewView(stored: analysis, entry: entry) { ids, title in
                    evidence = Evidence(title: title, ids: ids, stored: analysis)
                }
                .padding(.top, 6)
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
