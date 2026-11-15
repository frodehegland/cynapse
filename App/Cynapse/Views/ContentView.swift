// ContentView.swift — the models down the side; the chosen one's profile.

import SwiftUI
import AppKit
import ModelCheck
import ModelCheckModels

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    static let howItWorks = """
    Cynapse asks the model you choose a published, signed set of questions, worded as a writing app would word real \
    requests, and reads every answer by plain rules on this Mac; no AI marks another. The Character Check shows \
    whether it is right, makes things up, gives way to pressure, where it leans, and whether its answers change with \
    the date or who is asking. The Analysis Check shows how it draws concepts from a text, summarises and compares. \
    Every line of the results opens the exact questions and answers behind it. Nothing is averaged into a score, and \
    nothing of yours is sent.
    """
    @State private var addingCloud = false
    @State private var downloadingModel = false
    @State private var writingQuestions = false
    @State private var pastedQuestions: PastedQuestions?
    @State private var promptCopied = false
    @State private var pasteProblem: String?

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            List(selection: $app.selection) {
                section("On this Mac", app.entries.filter { if case .local = $0.kind { true } else { false } },
                        empty: "No downloaded models found. Models downloaded in Author or Knowledge Space appear here; or add a folder.")
                section("Built into macOS", app.entries.filter { $0.kind == .apple }, empty: nil)
                section("Cloud, with your own key", app.entries.filter { if case .cloud = $0.kind { true } else { false } },
                        empty: "None added.")
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                // How it works, in a paragraph, and the full guide under it.
                Text(Self.howItWorks)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { openWindow(id: "guide") } label: {
                    Label("User Guide", systemImage: "book")
                        .frame(maxWidth: .infinity)
                }
                .help("Everything Cynapse can do, and exactly how it works, with the source on GitHub")
                Divider().padding(.vertical, 2)
                // New questions from any online AI, carried by hand: the
                // prompt out on the clipboard, the reply back the same way.
                Button { copyForQuestions() } label: {
                    Label(promptCopied ? "Copied — paste it into an AI" : "Copy for AI Question Generation",
                          systemImage: promptCopied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .help("Copies a prompt for ChatGPT, Claude, Gemini or any AI, asking it to write new questions of every kind")
                Button { pasteQuestions() } label: {
                    Label("Paste AI Question Generated", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .help("Reads the AI's reply from the clipboard, so you can choose which of its questions to keep")
                Divider().padding(.top, 2)
                HStack {
                    Menu {
                        Button("Download a Model…") { downloadingModel = true }
                        Button("Add Model Folder…") { app.addFolder() }
                        Button("Add Cloud Model…") { addingCloud = true }
                        Divider()
                        Button("Write New Questions with an AI…") { writingQuestions = true }
                    } label: { Label("Add", systemImage: "plus") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Spacer()
                    Button { app.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Look for models again")
                }
                }
                .controlSize(.small)
                .padding(10)
            }
        } detail: {
            if let problem = app.bankProblem {
                ContentUnavailableView("The questions can't be used", systemImage: "xmark.seal",
                                       description: Text(problem))
            } else if let entry = app.selected {
                ModelDetailView(entry: entry)
            } else {
                ContentUnavailableView("Choose a model", systemImage: "cpu",
                                       description: Text("Pick a model on the left to see how it behaves, or check it."))
            }
        }
        .sheet(isPresented: $addingCloud) { AddCloudModelView() }
        .sheet(isPresented: $downloadingModel) { DownloadModelView() }
        .sheet(isPresented: $writingQuestions) { NewQuestionsView() }
        .sheet(item: $pastedQuestions) { NewQuestionsView(pasted: $0.reply) }
        .alert("The reply can't be read", isPresented: Binding(get: { pasteProblem != nil }, set: { if !$0 { pasteProblem = nil } })) {
            Button("OK") { pasteProblem = nil }
        } message: {
            Text(pasteProblem ?? "")
        }
    }

    private func copyForQuestions() {
        guard let bank = app.bank else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(QuestionWriting.mixedPrompt(bank: bank), forType: .string)
        promptCopied = true
        Task { try? await Task.sleep(for: .seconds(3)); promptCopied = false }
    }

    private func pasteQuestions() {
        guard let bank = app.bank else { return }
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        do {
            pastedQuestions = PastedQuestions(reply: try QuestionWriting.readMixed(text, bank: bank))
        } catch {
            pasteProblem = String(describing: error)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ entries: [ModelEntry], empty: String?) -> some View {
        Section(title) {
            if entries.isEmpty, let empty {
                Text(empty).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).lineLimit(1)
                    Text(app.status(of: entry))
                        .font(.caption)
                        .foregroundStyle(app.status(of: entry) == "changed" ? Color.red : Color.secondary)
                }
                .tag(entry.id)
                .contextMenu {
                    if case .cloud = entry.kind { Button("Remove") { app.removeCloud(entry) } }
                }
            }
        }
    }
}

struct AddCloudModelView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var provider: CloudModel.Provider = .anthropic
    @State private var model = CloudModel.Provider.anthropic.suggestedModel
    @State private var key = ""

    var body: some View {
        Form {
            Picker("Service", selection: $provider) {
                ForEach(CloudModel.Provider.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .onChange(of: provider) { _, new in model = new.suggestedModel }
            TextField("Model", text: $model)
            SecureField(Keychain.key(for: provider) == nil ? "Your key" : "Your key (already saved)", text: $key)
            Text("Your key is kept in your Keychain and sent only to \(provider.displayName). Cynapse has no keys of its own. A full check sends a few hundred short requests; what that costs depends on your plan.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    app.addCloud(provider: provider, model: model.trimmingCharacters(in: .whitespaces), key: key)
                    dismiss()
                }
                .disabled(model.trimmingCharacters(in: .whitespaces).isEmpty || (key.isEmpty && Keychain.key(for: provider) == nil))
            }
        }
    }
}

struct DownloadModelView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var id = "mlx-community/Qwen3-0.6B-4bit"

    var body: some View {
        Form {
            TextField("Hugging Face model", text: $id)
            Text("An MLX model's name on Hugging Face, such as mlx-community/Qwen3-0.6B-4bit. Each file is checked against the fingerprint Hugging Face publishes for it.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let d = app.downloading { ProgressView(value: d.fraction) { Text("Downloading \(d.id)…") } }
            if let problem = app.downloadProblem { Text(problem).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Download") { Task { await app.download(id); if app.downloadProblem == nil { dismiss() } } }
                    .disabled(app.downloading != nil || !id.contains("/"))
            }
        }
    }
}

/// A pasted reply, for the sheet that shows its questions.
struct PastedQuestions: Identifiable {
    let id = UUID()
    let reply: QuestionWriting.Reply
}
