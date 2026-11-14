// QuestionsView.swift — every question, and exactly what a model is sent,
// before anything is run. Nothing is hidden. The person's own questions,
// written with an online AI, are listed apart from the signed set.

import SwiftUI
import ModelCheck

struct QuestionsView: View {
    @Environment(AppModel.self) private var app
    @State private var selection: String?
    @State private var full = false
    @State private var writing = false

    var body: some View {
        if let bank = app.bank {
            @Bindable var app = app
            NavigationSplitView {
                List(selection: $selection) {
                    Section("Signed and published") {
                        ForEach(bank.items.filter { !$0.isOwn }, id: \.id) { row($0, bank) }
                    }
                    Section("Yours, written with an AI") {
                        if app.ownItems.isEmpty {
                            Text("None yet. Use Write New Questions to have ChatGPT, Claude or another AI write some.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(app.ownItems, id: \.id) { item in
                            row(item, bank)
                                .contextMenu { Button("Remove") { if selection == item.id { selection = nil }; app.removeOwn(item.id) } }
                        }
                    }
                }
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
                .safeAreaInset(edge: .bottom) {
                    Toggle("Ask my questions in checks", isOn: $app.askOwnQuestions)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help("Your questions are asked in quick and full checks, and the report says how many were yours. Weekly re-checks use the signed set alone.")
                }
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
                        Text("\(bank.items.count - app.ownItems.count) questions · \(bank.bank.kind) bank \(bank.bank.version)")
                        Text("Signed and verified. Choose one to see exactly what a model is sent.").foregroundStyle(.secondary)
                        if !app.ownItems.isEmpty {
                            Text("And \(app.ownItems.count) of your own, unsigned.").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button("Write New Questions with an AI…", systemImage: "sparkles") { writing = true }
                        .help("Copy a prompt for ChatGPT, Claude or any AI, and paste its questions back")
                }
            }
            .sheet(isPresented: $writing) { NewQuestionsView().environment(app) }
            .onReceive(NotificationCenter.default.publisher(for: .writeNewQuestions)) { _ in writing = true }
            .frame(minWidth: 860, minHeight: 560)
        } else {
            ContentUnavailableView("No questions", systemImage: "xmark.seal", description: Text(app.bankProblem ?? ""))
        }
    }

    private func row(_ item: Item, _ bank: Bank) -> some View {
        VStack(alignment: .leading) {
            Text(item.id).font(.body.monospaced())
            Text(item.module.rawValue + (item.axis.map { " · \($0)" } ?? "") + (bank.sentinels.contains(item.id) ? " · asked weekly" : ""))
                .font(.caption).foregroundStyle(.secondary)
        }
        .tag(item.id)
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

extension Notification.Name {
    /// Questions ▸ Write New Questions with an AI…
    static let writeNewQuestions = Notification.Name("CynapseWriteNewQuestions")
}
