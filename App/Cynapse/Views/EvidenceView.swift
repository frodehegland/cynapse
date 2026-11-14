// EvidenceView.swift — the exact prompts and answers behind a number,
// side by side for the two sides of a question and for the same question
// in different situations.

import SwiftUI
import ModelCheck

struct EvidenceView: View {
    @Environment(AppModel.self) private var app
    let evidence: Evidence
    /// Closes the panel.
    var close: () -> Void

    var body: some View {
        let records = ProfileStore.records(of: evidence.stored).filter { evidence.ids.contains($0.ask.itemId) }
        let byItem = Dictionary(grouping: records, by: \.ask.itemId)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
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
            if records.isEmpty {
                ContentUnavailableView("No transcript", systemImage: "doc.text",
                                       description: Text("This profile's transcript isn't here, so its questions and answers can't be shown."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(evidence.ids.filter { byItem[$0] != nil }, id: \.self) { id in
                            itemBlock(id, byItem[id] ?? [])
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 380)
    }

    @ViewBuilder
    private func itemBlock(_ id: String, _ records: [Record]) -> some View {
        let item = app.bank?.item(id)
        let outcome = app.bank.flatMap { bank in
            Scorer.outcomes(records.filter { $0.ask.pass == 1 && $0.ask.condition.id == records.first?.ask.condition.id }, bank: bank).first
        }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let outcome {
                    let rating = outcome.assessment(item: item)
                    Circle().fill(rating == .neutral ? Color.clear : rating.color)
                        .overlay(Circle().stroke(rating == .neutral ? Color.secondary.opacity(0.5) : .clear))
                        .frame(width: 8, height: 8)
                }
                Text(id).font(.caption.monospaced()).foregroundStyle(.secondary)
                if let outcome {
                    Text(outcome.plainText(item: item)).font(.callout)
                        .foregroundStyle(outcome.assessment(item: item) == .wrong ? Assessment.wrong.color : Color.primary)
                }
            }
            let bySituation = Dictionary(grouping: records) { "\($0.ask.condition.id)|\($0.ask.pass)" }
            ForEach(bySituation.keys.sorted(), id: \.self) { key in
                let group = (bySituation[key] ?? []).sorted { $0.ask.part < $1.ask.part }
                VStack(alignment: .leading, spacing: 6) {
                    let situation = LiveState.situation(group[0].ask.condition)
                    Text((situation.isEmpty ? "As asked plainly" : situation) + (group[0].ask.pass == 2 ? " (asked again unchanged)" : group[0].ask.pass >= 3 ? " (asked again to confirm)" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(group, id: \.ask.key) { record in
                            exchange(record).frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
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
        .background(.background, in: .rect(cornerRadius: 8))
    }
}
