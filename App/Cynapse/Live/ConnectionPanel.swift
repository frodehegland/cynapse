// ConnectionPanel.swift — a dot clicked in Connections, in the panel
// beside it: the question, and the answer the dot stands for (or, for a
// question's own dot, its answers as asked plainly first). Read from the
// exchanges the Live View already holds, so it works while a check runs.

import SwiftUI
import ModelCheck

struct ConnectionPanel: View {
    let pick: ConnectionPick
    let live: LiveState
    let bank: Bank?
    /// Hides the wording of charged questions.
    var privacy = false
    /// Closes the panel.
    var close: () -> Void

    private var item: Item? { bank?.item(pick.itemId) }
    private var answers: [Exchange] { live.exchanges.filter { $0.itemId == pick.itemId } }
    private var ratings: [String: Assessment] { live.assessments(bank: bank) }

    /// The clicked answer first; then plain askings, then the rest.
    private var ordered: [Exchange] {
        answers.sorted { a, b in
            func rank(_ e: Exchange) -> Int { e.key == pick.exchangeKey ? 0 : e.situation.isEmpty && !e.isConfirmation ? 1 : 2 }
            return rank(a) < rank(b)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pick.exchangeKey == nil ? "Question" : "Answer").font(.title3.weight(.semibold))
                    Text(pick.itemId).font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
                Spacer()
                Button { close() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    .help("Close")
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if answers.isEmpty {
                        if let prompt = item?.prompt, !(privacy && item?.module == .values) {
                            Text(prompt).font(.system(.title3, design: .serif)).foregroundStyle(Color.question)
                                .textSelection(.enabled)
                        }
                        Text(live.askedItems.contains(pick.itemId) ? "Its answers have scrolled out of the view." : "Not asked yet in this check.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        let ordered = ordered
                        if let first = ordered.first { exchange(first) }
                        let rest = Array(ordered.dropFirst())
                        if !rest.isEmpty {
                            DisclosureGroup("Asked \(rest.count) other time\(rest.count == 1 ? "" : "s")") {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(rest) { exchange($0) }
                                }
                                .padding(.top, 6)
                            }
                            .font(.caption)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 380, maxHeight: .infinity, alignment: .top)
    }

    private func exchange(_ e: Exchange) -> some View {
        let rating = ratings[e.outcomeKey]
        return VStack(alignment: .leading, spacing: 8) {
            Text((e.situation.isEmpty ? "As asked plainly" : e.situation) + (e.isConfirmation ? " (asked again to confirm)" : ""))
                .font(.caption).foregroundStyle(.secondary)
            if let system = e.system, !system.isEmpty {
                Text("Instructions: " + system).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if privacy && e.isSensitive {
                Text("A charged question; its wording is hidden.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text(e.prompt).font(.system(.body, design: .serif)).foregroundStyle(Color.question)
                    .textSelection(.enabled)
            }
            Divider()
            Text(e.answer.isEmpty ? "No answer yet." : e.answer).textSelection(.enabled)
            if let plain = e.plain {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(rating.map { $0 == .neutral ? Color.clear : $0.color } ?? .clear)
                        .overlay(Circle().stroke(rating == nil || rating == .neutral ? Color.secondary.opacity(0.5) : .clear))
                        .frame(width: 8, height: 8)
                    Text(plain).font(.callout.weight(.medium))
                        .foregroundStyle(rating == .wrong ? Assessment.wrong.color : Color.primary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
    }
}
