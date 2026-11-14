// EvidenceView.swift — the questions and answers behind a line of the
// report, in the panel beside it.
//
// Problems first; each question as it was asked plainly, then — tucked
// away — the same question in the other situations it was asked in. The
// transcript is read once, away from the main thread, so the panel opens at
// once and fills as soon as it is read.

import SwiftUI
import ModelCheck

struct EvidenceView: View {
    @Environment(AppModel.self) private var app
    let evidence: Evidence
    /// Closes the panel.
    var close: () -> Void
    /// False only for snapshots, which can't draw a scroll view.
    var scrolls = true

    /// The answers to this line's questions, by question; nil while reading.
    @State private var byItem: [String: [Record]]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(evidence.title).font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { close() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    .help("Close")
            }
            .padding(20)
            Divider()
            if let byItem {
                if byItem.isEmpty {
                    ContentUnavailableView("No answers to show", systemImage: "doc.text",
                                           description: Text("This check's transcript doesn't hold answers to these questions."))
                } else if scrolls {
                    ScrollView { list(byItem) }
                } else {
                    list(byItem)
                }
            } else {
                ProgressView("Reading the answers…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 380, maxHeight: .infinity, alignment: .top)
        .task(id: evidence.id) { await load() }
    }

    /// Reads the transcript in the background and keeps only this line's
    /// questions.
    private func load() async {
        byItem = nil
        let stored = evidence.stored
        let ids = Set(evidence.ids)
        let records = await Task.detached(priority: .userInitiated) {
            ProfileStore.records(of: stored).filter { ids.contains($0.ask.itemId) }
        }.value
        byItem = Dictionary(grouping: records, by: \.ask.itemId)
    }

    /// The questions, those that went wrong first.
    private func ordered(_ byItem: [String: [Record]]) -> [String] {
        let rank: (String) -> Assessment = { id in plainOutcome(id, byItem[id] ?? [])?.assessment(item: app.bank?.item(id)) ?? .neutral }
        return evidence.ids.filter { byItem[$0] != nil }.sorted { rank($0) < rank($1) }
    }

    private func list(_ byItem: [String: [Record]]) -> some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(ordered(byItem), id: \.self) { id in
                itemBlock(id, byItem[id] ?? [])
            }
        }
        .padding(16)
    }

    /// The question as asked plainly, the first time.
    private func plainOutcome(_ id: String, _ records: [Record]) -> Scorer.Outcome? {
        guard let bank = app.bank else { return nil }
        let plain = records.filter { $0.ask.pass == 1 && isPlain($0.ask.condition) }
        return Scorer.outcomes(plain.isEmpty ? records : plain, bank: bank).first
    }

    private func isPlain(_ condition: Condition) -> Bool {
        condition.date.id == "none" && condition.context.text.isEmpty && condition.depth.priorTurns == 0
    }

    @ViewBuilder
    private func itemBlock(_ id: String, _ records: [Record]) -> some View {
        let item = app.bank?.item(id)
        let outcome = plainOutcome(id, records)
        let rating = outcome?.assessment(item: item) ?? .neutral
        let groups = Dictionary(grouping: records) { "\($0.ask.condition.id)|\($0.ask.pass)" }
        let keys = groups.keys.sorted()
        let plainKey = keys.first { key in
            groups[key]?.first.map { $0.ask.pass == 1 && isPlain($0.ask.condition) } ?? false
        } ?? keys.first
        let others = keys.filter { $0 != plainKey }

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(rating == .neutral ? Color.clear : rating.color)
                    .overlay(Circle().stroke(rating == .neutral ? Color.secondary.opacity(0.5) : .clear))
                    .frame(width: 8, height: 8)
                if let outcome {
                    Text(outcome.plainText(item: item)).font(.callout.weight(.medium))
                        .foregroundStyle(rating == .wrong ? Assessment.wrong.color : Color.primary)
                }
                Spacer()
                Text(id).font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
            if let plainKey, let group = groups[plainKey] {
                situationBlock(group)
            }
            if !others.isEmpty {
                DisclosureGroup("Asked again in \(others.count) other situation\(others.count == 1 ? "" : "s")") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(others, id: \.self) { key in situationBlock(groups[key] ?? []) }
                    }
                    .padding(.top, 6)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private func situationBlock(_ group: [Record]) -> some View {
        let sorted = group.sorted { $0.ask.part < $1.ask.part }
        if let first = sorted.first {
            VStack(alignment: .leading, spacing: 6) {
                let situation = LiveState.situation(first.ask.condition)
                Text((situation.isEmpty ? "As asked plainly" : situation)
                     + (first.ask.pass == 2 ? " (asked again unchanged)" : first.ask.pass >= 3 ? " (asked again to confirm)" : ""))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(sorted, id: \.ask.key) { record in exchange(record) }
            }
        }
    }

    private func exchange(_ record: Record) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.ask.conversation.last?.text ?? "")
                .font(.system(.body, design: .serif))
                .textSelection(.enabled)
            ForEach(Array((record.ask.followUps ?? []).enumerated()), id: \.offset) { _, f in
                Text("Then: " + f).font(.system(.callout, design: .serif)).foregroundStyle(.secondary)
            }
            Divider()
            if let likelihoods = record.likelihoods {
                Text("Likelihoods " + LiveState.likelihoodText(likelihoods, options: record.ask.options ?? []))
            }
            ForEach(Array(record.replies.enumerated()), id: \.offset) { _, reply in
                Text(reply).textSelection(.enabled)
            }
            Text("\(record.method) · \(String(format: "%.1f", record.seconds)) s")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 8))
    }
}
