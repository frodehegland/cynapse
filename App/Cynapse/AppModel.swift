// AppModel.swift — the models, the question bank, the profiles, and the
// check that is running.

import Foundation
import Observation
import AppKit
import ModelCheck
import ModelCheckModels

@Observable @MainActor
final class AppModel {

    /// The key the question bank must be signed with. Its private half is
    /// held by Frode Hegland, outside the repository.
    static let bankPublicKey = "tqNYCtQ/NhflQhwr5RIo2BrSwS8HBkVCfaHhDt7m4E0="

    var entries: [ModelEntry] = []
    var selection: ModelEntry.ID?
    var bank: Bank?
    var bankProblem: String?
    var profiles: [ModelEntry.ID: [StoredProfile]] = [:]
    /// Each local model's current fingerprint, worked out in the background.
    var fingerprints: [ModelEntry.ID: (hash: String, size: Int64)] = [:]
    var fingerprinting: Set<ModelEntry.ID> = []

    var runningEntry: ModelEntry.ID?
    var runProblem: String?
    let live = LiveState()
    var showLiveView = false
    private var runTask: Task<Void, Never>?

    init() {
        loadBank()
        refresh()
    }

    var selected: ModelEntry? { entries.first { $0.id == selection } }

    // MARK: Bank

    func loadBank() {
        guard let url = Bundle.main.url(forResource: "pilot-bank-v0.2", withExtension: "json") else {
            bankProblem = "The question bank is missing from the app."
            return
        }
        do {
            bank = try BankSignature.loadVerified(url, publicKey: Self.bankPublicKey)
            bankProblem = nil
        } catch {
            bank = nil
            bankProblem = "\(error)"
        }
    }

    // MARK: Models

    func refresh() {
        entries = ModelLibrary.all()
        for entry in entries { profiles[entry.id] = ProfileStore.profiles(for: entry) }
        if selection == nil { selection = entries.first?.id }
        for entry in entries { fingerprintIfNeeded(entry) }
    }

    func fingerprintIfNeeded(_ entry: ModelEntry) {
        guard case .local(let path) = entry.kind, fingerprints[entry.id] == nil, !fingerprinting.contains(entry.id) else { return }
        fingerprinting.insert(entry.id)
        let id = entry.id
        Task.detached(priority: .utility) {
            let result = try? ModelFingerprint.sha256(ofFolder: URL(fileURLWithPath: path))
            await MainActor.run {
                self.fingerprinting.remove(id)
                if let result { self.fingerprints[id] = result }
            }
        }
    }

    /// "checked", "not checked", "changed" (its files differ from those
    /// last checked) or "being checked".
    func status(of entry: ModelEntry) -> String {
        if runningEntry == entry.id { return "being checked" }
        guard let latest = profiles[entry.id]?.first else { return "not checked" }
        if let now = fingerprints[entry.id]?.hash, let then = latest.profile.model.sha256, now != then { return "changed" }
        return "checked"
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a folder holding a downloaded MLX model, or a folder of them."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        ModelLibrary.addFolder(url)
        refresh()
    }

    var downloading: (id: String, fraction: Double)?
    var downloadProblem: String?

    /// Downloads an MLX model from Hugging Face into Cynapse's own folder.
    func download(_ id: String) async {
        downloadProblem = nil
        downloading = (id, 0)
        do {
            _ = try await ModelDownloader.download(id) { fraction in
                Task { @MainActor in self.downloading = (id, fraction) }
            }
            downloading = nil
            refresh()
            selection = entries.first { $0.name == id }?.id
        } catch {
            downloading = nil
            downloadProblem = error.localizedDescription
        }
    }

    func addCloud(provider: CloudModel.Provider, model: String, key: String?) {
        if let key, !key.isEmpty { Keychain.setKey(key, for: provider) }
        let entry = ModelEntry(kind: .cloud(provider: provider, model: model), name: "\(model)")
        ModelLibrary.addCloud(entry)
        refresh()
        selection = entry.id
    }

    func removeCloud(_ entry: ModelEntry) {
        ModelLibrary.removeCloud(entry)
        refresh()
    }

    // MARK: Checking

    func startCheck(_ entry: ModelEntry, mode: RunMode) {
        guard runningEntry == nil, let bank else { return }
        runProblem = nil
        let model: any CheckedModel
        do {
            model = try ModelLibrary.model(for: entry, fingerprint: fingerprints[entry.id])
        } catch {
            runProblem = error.localizedDescription
            return
        }
        // A model whose files changed since its last check starts afresh.
        let transcript = ProfileStore.currentTranscript(for: entry)
        if let last = profiles[entry.id]?.first?.profile.model.sha256, let now = fingerprints[entry.id]?.hash, last != now {
            try? FileManager.default.removeItem(at: transcript)
        }

        runningEntry = entry.id
        live.reset(bank: bank, verified: true)
        let (stream, continuation) = AsyncStream<CheckEvent>.makeStream(bufferingPolicy: .unbounded)

        // Events reach the view in order, on the main actor.
        Task { @MainActor in
            for await event in stream { self.live.apply(event) }
        }

        runTask = Task.detached(priority: .userInitiated) { [bank] in
            let runner = Runner(bank: bank, model: model, transcriptURL: transcript)
            runner.onEvent = { continuation.yield($0) }
            if let asks = try? runner.plan(mode, likelihoods: false) {
                await MainActor.run { self.live.setPlan(asks) }
            }
            do {
                let profile = try await runner.check(mode)
                continuation.finish()
                await MainActor.run {
                    _ = try? ProfileStore.save(profile, for: entry)
                    self.profiles[entry.id] = ProfileStore.profiles(for: entry)
                    self.runningEntry = nil
                }
            } catch is CancellationError {
                continuation.finish()
                await MainActor.run { self.runningEntry = nil; self.live.running = false }
            } catch {
                continuation.finish()
                await MainActor.run {
                    self.runProblem = "The check stopped: \(error.localizedDescription). It will carry on from here next time."
                    self.runningEntry = nil
                    self.live.running = false
                }
            }
        }
    }

    /// Stops the check; what was answered is kept, and the next check
    /// carries on from there.
    func stopCheck() {
        runTask?.cancel()
    }

    // MARK: Opening from Author and Knowledge Space

    /// `cynapse://check?model=<name or id>`: selects that model.
    func open(_ url: URL) {
        guard url.scheme == "cynapse" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let wanted = items.first(where: { $0.name == "model" })?.value,
           let entry = entries.first(where: { $0.name == wanted || $0.id == wanted }) {
            selection = entry.id
        }
    }

    // MARK: Export

    func export(_ stored: StoredProfile) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "The profile and its full transcript will be copied here."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        try? ProfileStore.export(stored, to: folder)
    }
}
