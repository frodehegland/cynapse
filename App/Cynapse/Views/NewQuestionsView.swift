// NewQuestionsView.swift — new questions from a large online AI, carried
// by hand (as Knowledge Space's Copy Prompt and Paste from AI): Cynapse
// writes the prompt, the person takes it to ChatGPT, Claude, Gemini or any
// other, and pastes the reply back. Cynapse holds no key and sends nothing.
// Each question that comes back is shown with any problem found in it, and
// only those the person ticks are kept.

import SwiftUI
import AppKit
import ModelCheck

struct NewQuestionsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var kind: QuestionWriting.Kind = .facts
    @State private var count = 8
    @State private var axis = "economic"
    @State private var about = ""
    @State private var copied = false
    @State private var showPrompt = false
    @State private var reply: QuestionWriting.Reply?
    @State private var problem: String?
    @State private var keep: Set<String> = []
    @State private var added: Int?

    private static let ais: [(name: String, url: String)] = [
        ("ChatGPT", "https://chatgpt.com/"),
        ("Claude", "https://claude.ai/new"),
        ("Gemini", "https://gemini.google.com/app"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    Picker("Kind", selection: $kind) {
                        ForEach(QuestionWriting.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    Text(kind.purpose).font(.caption).foregroundStyle(.secondary)
                    if kind == .contested, let bank = app.signedBank {
                        Picker("About", selection: $axis) {
                            ForEach(bank.axes.keys.sorted(), id: \.self) { key in
                                Text(key.prefix(1).uppercased() + key.dropFirst()).tag(key)
                            }
                        }
                        if let poles = bank.axes[axis] {
                            Text("Between “\(poles.negative)” and “\(poles.positive)”; the AI is asked for half each way.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Stepper("\(count) questions", value: $count, in: 2...30, step: 2)
                    TextField("Subject (optional)", text: $about, prompt: Text("medicine, Norwegian history, space…"))
                } header: {
                    Text("1. What to ask for")
                }

                Section {
                    HStack {
                        Button(copied ? "Copied" : "Copy Prompt", systemImage: copied ? "checkmark" : "doc.on.doc") { copyPrompt() }
                            .keyboardShortcut("c", modifiers: [.command, .shift])
                        Button(showPrompt ? "Hide Prompt" : "Show Prompt") { showPrompt.toggle() }
                        Spacer()
                        ForEach(Self.ais, id: \.name) { ai in
                            Button(ai.name) { if let url = URL(string: ai.url) { openURL(url) } }
                                .help("Opens \(ai.name) in your browser. Paste the prompt there.")
                        }
                    }
                    if showPrompt {
                        ScrollView {
                            Text(prompt).font(.caption.monospaced()).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 160)
                    }
                    Text("Paste the prompt into any AI you use, in its own app or website. Cynapse sends nothing and needs no key.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("2. Take the prompt to an AI")
                }

                Section {
                    HStack {
                        Button("Paste Reply", systemImage: "doc.on.clipboard") { paste() }
                            .keyboardShortcut("v", modifiers: [.command, .shift])
                        Text("Copy the AI's whole reply first.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let problem {
                        Text(problem).foregroundStyle(Assessment.wrong.color).fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("3. Bring its reply back")
                }

                if let reply {
                    Section {
                        ForEach(reply.proposals) { proposal in proposalRow(proposal) }
                    } header: {
                        Text("4. Keep the good ones" + (reply.ai.map { " — written by \($0)" } ?? ""))
                    } footer: {
                        Text("Your questions are kept apart from the signed set, and any report that includes them says so. Check each one yourself: the AI may be wrong.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if let added { Text("Added \(added) question\(added == 1 ? "" : "s").").foregroundStyle(.secondary) }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add \(keep.count) Question\(keep.count == 1 ? "" : "s")") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(keep.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 640, height: 720)
        .onChange(of: kind) { _, _ in clearReply() }
        .onChange(of: axis) { _, _ in clearReply() }
    }

    private var prompt: String {
        guard let bank = app.bank else { return "" }
        return QuestionWriting.prompt(kind: kind, count: count, axis: kind == .contested ? axis : nil, about: about, bank: bank)
    }

    private func proposalRow(_ proposal: QuestionWriting.Proposal) -> some View {
        Toggle(isOn: Binding(get: { keep.contains(proposal.id) },
                             set: { if $0 { keep.insert(proposal.id) } else { keep.remove(proposal.id) } })) {
            VStack(alignment: .leading, spacing: 3) {
                Text(proposal.text.isEmpty ? "(no question)" : proposal.text)
                    .font(.system(.body, design: .serif)).foregroundStyle(Color.question)
                if !proposal.detail.isEmpty { Text(proposal.detail).font(.caption).foregroundStyle(.secondary) }
                ForEach(proposal.problems, id: \.self) { Text($0).font(.caption).foregroundStyle(Assessment.wrong.color) }
            }
        }
        .toggleStyle(.checkbox)
    }

    private func copyPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }

    private func paste() {
        problem = nil
        added = nil
        guard let bank = app.bank else { return }
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        do {
            let read = try QuestionWriting.read(text, kind: kind, axis: kind == .contested ? axis : nil, bank: bank)
            reply = read
            // Ticked when nothing is wrong with them; the rest left for the person to judge.
            keep = Set(read.proposals.filter(\.problems.isEmpty).map(\.id))
        } catch {
            reply = nil
            keep = []
            problem = String(describing: error)
        }
    }

    private func add() {
        guard let reply else { return }
        let items = reply.proposals.filter { keep.contains($0.id) }.map(\.item)
        app.addOwn(items)
        added = items.count
        clearReply()
    }

    private func clearReply() {
        reply = nil
        keep = []
        problem = nil
    }
}
