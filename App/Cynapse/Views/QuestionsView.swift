// QuestionsView.swift — every question, and exactly what a model is sent,
// before anything is run. Nothing is hidden.

import SwiftUI
import ModelCheck

struct QuestionsView: View {
    @Environment(AppModel.self) private var app
    @State private var selection: String?
    @State private var full = false

    var body: some View {
        if let bank = app.bank {
            NavigationSplitView {
                List(bank.items, id: \.id, selection: $selection) { item in
                    VStack(alignment: .leading) {
                        Text(item.id).font(.body.monospaced())
                        Text(item.module.rawValue + (item.axis.map { " · \($0)" } ?? "") + (bank.sentinels.contains(item.id) ? " · asked weekly" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            } detail: {
                if let id = selection, let item = bank.item(id) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(item.id).font(.title2.monospaced())
                            if let note = item.note { Text(note).foregroundStyle(.secondary) }
                            Text("Scored by: \(item.scoring.type.rawValue)" + (item.scoring.accept.map { " · accepted: \($0.joined(separator: ", "))" } ?? ""))
                                .font(.callout).foregroundStyle(.secondary)
                            Toggle("Show the full check's versions too", isOn: $full)
                            ForEach(asks(item, bank), id: \.key) { ask in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(LiveState.situation(ask.condition).isEmpty ? "As asked plainly" : LiveState.situation(ask.condition))
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let system = ask.system { Text("System: " + system).font(.caption.monospaced()) }
                                    Text(ask.conversation.last?.text ?? "").font(.system(.body, design: .serif)).textSelection(.enabled)
                                    ForEach(ask.followUps ?? [], id: \.self) { Text("Then: " + $0).font(.system(.callout, design: .serif)) }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.background.secondary, in: .rect(cornerRadius: 8))
                            }
                        }
                        .padding(24)
                    }
                } else {
                    VStack(spacing: 10) {
                        Text("\(bank.items.count) questions · \(bank.bank.kind) bank \(bank.bank.version)")
                        Text("Signed and verified. Choose one to see exactly what a model is sent.").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minWidth: 860, minHeight: 560)
        } else {
            ContentUnavailableView("No questions", systemImage: "xmark.seal", description: Text(app.bankProblem ?? ""))
        }
    }

    private func asks(_ item: Item, _ bank: Bank) -> [Ask] {
        let runner = Runner(bank: bank, model: PlanOnlyModel())
        let all = (try? runner.plan(full ? .full : .quick, likelihoods: false)) ?? []
        return all.filter { $0.itemId == item.id }
    }
}

/// Stands in for a model when only the plan is wanted: never asked anything.
struct PlanOnlyModel: CheckedModel {
    var identity: ModelIdentity { ModelIdentity(name: "plan", provider: "none") }
    func reply(system: String?, conversation: [Turn]) async throws -> String { "" }
}
