// ContentView.swift — the models down the side; the chosen one's profile.

import SwiftUI
import ModelCheck
import ModelCheckModels

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @State private var addingCloud = false
    @State private var downloadingModel = false

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
                HStack {
                    Menu {
                        Button("Download a Model…") { downloadingModel = true }
                        Button("Add Model Folder…") { app.addFolder() }
                        Button("Add Cloud Model…") { addingCloud = true }
                    } label: { Label("Add", systemImage: "plus") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Spacer()
                    Button { app.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Look for models again")
                }
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
