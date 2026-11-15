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
    /// The signed bank and the person's own questions after it.
    var bank: Bank?
    /// The signed bank alone, exactly as published.
    var signedBank: Bank?
    /// Questions the person wrote with an online AI (Questions ▸ Write New
    /// Questions with an AI…), unsigned and kept apart.
    var ownItems: [Item] = []
    var bankProblem: String?
    /// The Analysis Check's passages, asked once per model; and whether
    /// they are signed (a draft is run, and its profile says so).
    var analysisBank: Bank?
    var analysisSigned = false
    /// The bank of the check the Live View is showing.
    var liveBank: Bank?
    /// Every question known, for opening the evidence behind any line.
    var lookupBank: Bank? {
        guard var all = bank else { return analysisBank }
        all.items += analysisBank?.items ?? []
        return all
    }

    /// Whether checks ask the person's own questions too (weekly re-checks
    /// never do: they are measured against the signed set alone).
    var askOwnQuestions = UserDefaults.standard.object(forKey: "AskOwnQuestions") as? Bool ?? true {
        didSet { UserDefaults.standard.set(askOwnQuestions, forKey: "AskOwnQuestions") }
    }
    var profiles: [ModelEntry.ID: [StoredProfile]] = [:]
    /// Each local model's current fingerprint, worked out in the background.
    var fingerprints: [ModelEntry.ID: (hash: String, size: Int64)] = [:]
    var fingerprinting: Set<ModelEntry.ID> = []

    /// The models chosen to judge what matching can't read (Settings ▸
    /// Judges): two or three from different labs.
    var judgeIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: "JudgeModels") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "JudgeModels") }
    }
    var judging: String?

    var runningEntry: ModelEntry.ID?
    var runProblem: String?
    let live = LiveState()
    var showLiveView = false
    private var runTask: Task<Void, Never>?

    init() {
        loadBank()
        refresh()
        if !Headless.requested && !Snapshot.requested { WeeklyChecks.start(self) }
    }

    var selected: ModelEntry? { entries.first { $0.id == selection } }

    // MARK: Bank

    func loadBank() {
        guard let url = Bundle.main.url(forResource: "pilot-bank-v0.2", withExtension: "json") else {
            bankProblem = "The question bank is missing from the app."
            return
        }
        do {
            signedBank = try BankSignature.loadVerified(url, publicKey: Self.bankPublicKey)
            bankProblem = nil
        } catch {
            signedBank = nil
            bankProblem = "\(error)"
        }
        ownItems = OwnQuestionsStore.load()
        bank = signedBank?.adding(own: ownItems)
        loadAnalysisBank()
    }

    /// The Analysis passages: verified when signed; a draft with no
    /// signature yet is still run, marked unsigned; a bad signature is refused.
    func loadAnalysisBank() {
        guard let url = Bundle.main.url(forResource: "analysis-bank-v0.1", withExtension: "json") else { return }
        if FileManager.default.fileExists(atPath: url.path + ".sig") {
            analysisBank = try? BankSignature.loadVerified(url, publicKey: Self.bankPublicKey)
            analysisSigned = analysisBank != nil
        } else {
            analysisBank = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Bank.self, from: $0) }
            analysisSigned = false
        }
    }

    /// The model's latest Analysis Check, if any.
    func latestAnalysis(_ entry: ModelEntry) -> StoredProfile? {
        profiles[entry.id]?.first { $0.profile.run.kind == .analysis }
    }

    /// Whether the model has changed since its Analysis Check: its files,
    /// or for Apple's model, the version of macOS it comes with.
    func analysisOutdated(_ entry: ModelEntry) -> Bool {
        guard let then = latestAnalysis(entry)?.profile.model else { return false }
        if let now = fingerprints[entry.id]?.hash, let was = then.sha256 { return now != was }
        if case .apple = entry.kind, let model = try? ModelLibrary.model(for: entry, fingerprint: nil) {
            return model.identity.runtime?.version != then.runtime?.version
        }
        return false
    }

    /// Keeps new questions of the person's own.
    func addOwn(_ items: [Item]) {
        ownItems += items.filter { item in !ownItems.contains { $0.id == item.id } }
        OwnQuestionsStore.save(ownItems)
        bank = signedBank?.adding(own: ownItems)
    }

    func removeOwn(_ id: String) {
        ownItems.removeAll { $0.id == id }
        OwnQuestionsStore.save(ownItems)
        bank = signedBank?.adding(own: ownItems)
    }

    // MARK: Models

    func refresh() {
        entries = ModelLibrary.all()
        for entry in entries { profiles[entry.id] = filled(ProfileStore.profiles(for: entry)) }
        if selection == nil { selection = entries.first?.id }
        for entry in entries { fingerprintIfNeeded(entry) }
    }

    /// Older profiles given the item lists newer reports use.
    private func filled(_ stored: [StoredProfile]) -> [StoredProfile] {
        guard let bank else { return stored }
        return stored.map { var s = $0; s.profile = s.profile.fillingItemLists(bank: bank); return s }
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
        if WeeklyChecks.watchLog(for: entry).last?.alert == true { return "answers changed" }
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
        guard runningEntry == nil, let signedBank, let merged = bank else { return }
        let analysing = mode == .analysis
        guard !analysing || analysisBank != nil else { runProblem = "The Analysis passages are missing from the app, or their signature doesn't match."; return }
        let bank = analysing ? analysisBank! : mode != .weekly && askOwnQuestions ? merged : signedBank
        let unsigned = analysing && !analysisSigned
        runProblem = nil
        let model: any CheckedModel
        do {
            model = try ModelLibrary.model(for: entry, fingerprint: fingerprints[entry.id])
        } catch {
            runProblem = error.localizedDescription
            return
        }
        // A model whose files changed since its last check starts afresh.
        let transcript = ProfileStore.currentTranscript(for: entry, analysis: analysing)
        if let last = profiles[entry.id]?.first?.profile.model.sha256, let now = fingerprints[entry.id]?.hash, last != now {
            try? FileManager.default.removeItem(at: transcript)
        }

        runningEntry = entry.id
        liveBank = bank
        live.reset(bank: bank, verified: !unsigned)
        let (stream, continuation) = AsyncStream<CheckEvent>.makeStream(bufferingPolicy: .unbounded)

        // Events reach the view in order, on the main actor.
        Task { @MainActor in
            for await event in stream { self.live.apply(event) }
        }

        runTask = Task.detached(priority: .userInitiated) { [bank] in
            let runner = Runner(bank: bank, model: model, transcriptURL: transcript)
            runner.onEvent = { continuation.yield($0) }
            if mode == .weekly { runner.seed = await WeeklyChecks.seed(for: entry) }
            if let asks = try? runner.plan(mode, likelihoods: false) {
                await MainActor.run { self.live.setPlan(asks) }
            }
            do {
                var profile = try await runner.check(mode)
                if unsigned { profile.bank.unsigned = true }
                continuation.finish()
                await MainActor.run { [profile] in
                    let stored = try? ProfileStore.save(profile, for: entry, transcript: transcript)
                    self.profiles[entry.id] = self.filled(ProfileStore.profiles(for: entry))
                    if mode == .weekly, let stored {
                        WeeklyChecks.finished(stored, entry: entry, profiles: self.profiles[entry.id] ?? [], bank: bank)
                    }
                    self.runningEntry = nil
                    if mode != .weekly, let stored { self.judge(stored, entry: entry, bank: bank) }
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

    /// The chosen judges read the answers a check can't score mechanically;
    /// their reports are added to the profile.
    func judge(_ stored: StoredProfile, entry: ModelEntry, bank: Bank) {
        let judges = judgeIDs.compactMap { id in entries.first { $0.id == id && $0.id != entry.id } }
            .compactMap { try? ModelLibrary.model(for: $0, fingerprint: fingerprints[$0.id]) }
        guard !judges.isEmpty else { return }
        judging = "Judges are reading the answers…"
        let records = ProfileStore.records(of: stored)
        Task.detached(priority: .utility) {
            let reports = try? await Judging.judge(records: records, bank: bank, tested: stored.profile.model, judges: judges) { message in
                Task { @MainActor in self.judging = message }
            }
            await MainActor.run {
                self.judging = nil
                guard let reports, !reports.isEmpty else { return }
                var profile = stored.profile
                profile.judges = reports
                profile.judgeAgreement = Judging.agreement(reports)
                profile.report = profile.reportLines().map { "\($0.heading): \($0.text)" }
                try? profile.jsonData().write(to: stored.url)
                self.profiles[entry.id] = self.filled(ProfileStore.profiles(for: entry))
            }
        }
    }

    /// The Live View with no check running: the selected model's last check
    /// replayed from its transcript — real questions and answers, in order.
    func replayLatest() {
        guard runningEntry == nil, let bank, let entry = selected ?? entries.first,
              let stored = profiles[entry.id]?.first(where: { $0.profile.run.kind == .quick || $0.profile.run.kind == .full })
                ?? profiles[entry.id]?.first(where: { $0.profile.run.kind != .analysis }) else { return }
        let records = ProfileStore.records(of: stored)
        guard !records.isEmpty else { return }
        liveBank = bank
        live.reset(bank: bank, verified: true)
        live.setPlan(records.map(\.ask))
        live.apply(.started(model: stored.profile.model, bank: bank.bank, planned: records.count, mode: stored.profile.run.kind))
        for (index, record) in records.enumerated() {
            live.apply(.asking(record.ask, index: index + 1, of: records.count))
            live.apply(.answered(record, index: index + 1, of: records.count))
        }
        for outcome in Scorer.outcomes(records, bank: bank) {
            live.apply(.scored(outcome, plain: outcome.plainText(item: bank.item(outcome.itemId))))
        }
        live.apply(.finished(stored.profile))
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
