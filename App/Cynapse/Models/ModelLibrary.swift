// ModelLibrary.swift — the models there are to check.
//
// Downloaded models are found where Author and Knowledge Space keep them
// (their shared App Group), and in any folder the person adds. Apple's
// built-in model is listed when this Mac has it. Cloud models are the ones
// the person has added, with their own key.

import Foundation
import ModelCheck
import ModelCheckModels

struct ModelEntry: Identifiable, Hashable, Codable {
    enum Kind: Hashable, Codable {
        case local(path: String)
        case apple
        case cloud(provider: CloudModel.Provider, model: String)
    }
    var kind: Kind
    var name: String

    var id: String {
        switch kind {
        case .local(let path): "local:" + path
        case .apple: "apple"
        case .cloud(let provider, let model): "cloud:\(provider.rawValue):\(model)"
        }
    }

    /// Where its profiles are kept: one folder per model.
    var storeKey: String {
        id.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }.reduce("") { $0 + String($1) }
    }

    var kindLabel: String {
        switch kind {
        case .local: "On this Mac"
        case .apple: "Built into macOS"
        case .cloud(let provider, _): provider.displayName
        }
    }
}

enum ModelLibrary {

    static let appGroup = "group.com.liquid.models"

    /// The folder Author and Knowledge Space download models into.
    static var sharedFolder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("Library/Application Support/Liquid Models", isDirectory: true)
    }

    /// Where Cynapse writes the profiles it shares with the other apps.
    static var sharedProfilesFolder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("Library/Application Support/Cynapse Profiles", isDirectory: true)
    }

    /// A folder holding a whole model: its configuration and weights.
    static func isModelFolder(_ url: URL) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return files.contains("config.json") && files.contains { $0.hasSuffix(".safetensors") }
    }

    /// Every downloaded model under `root`: the Hugging Face cache's
    /// snapshots (`models--org--name/snapshots/<rev>`) and the older
    /// `models/org/name` layout.
    static func models(in root: URL) -> [ModelEntry] {
        let fm = FileManager.default
        var found: [ModelEntry] = []
        if isModelFolder(root) {
            found.append(ModelEntry(kind: .local(path: root.path), name: root.lastPathComponent))
        }
        for repo in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where repo.lastPathComponent.hasPrefix("models--") {
            let name = repo.lastPathComponent.dropFirst("models--".count).replacingOccurrences(of: "--", with: "/")
            let snapshots = repo.appendingPathComponent("snapshots")
            for revision in (try? fm.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil)) ?? [] where isModelFolder(revision) {
                found.append(ModelEntry(kind: .local(path: revision.path), name: name))
            }
        }
        let legacy = root.appendingPathComponent("models")
        for org in (try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)) ?? [] {
            for model in (try? fm.contentsOfDirectory(at: org, includingPropertiesForKeys: nil)) ?? [] where isModelFolder(model) {
                found.append(ModelEntry(kind: .local(path: model.path), name: "\(org.lastPathComponent)/\(model.lastPathComponent)"))
            }
        }
        return found
    }

    // MARK: Folders the person added (kept as security-scoped bookmarks)

    private static let bookmarksKey = "AddedModelFolders"

    static func addedFolders() -> [URL] {
        let bookmarks = UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] ?? []
        return bookmarks.compactMap { data in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale) else { return nil }
            _ = url.startAccessingSecurityScopedResource()
            return url
        }
    }

    static func addFolder(_ url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        var bookmarks = UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] ?? []
        bookmarks.append(data)
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }

    // MARK: Cloud models the person added

    private static let cloudKey = "CloudModels"

    static func cloudModels() -> [ModelEntry] {
        guard let data = UserDefaults.standard.data(forKey: cloudKey),
              let entries = try? JSONDecoder().decode([ModelEntry].self, from: data) else { return [] }
        return entries
    }

    static func addCloud(_ entry: ModelEntry) {
        var entries = cloudModels().filter { $0.id != entry.id }
        entries.append(entry)
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: cloudKey) }
    }

    static func removeCloud(_ entry: ModelEntry) {
        let entries = cloudModels().filter { $0.id != entry.id }
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: cloudKey) }
    }

    // MARK: Everything

    static func all() -> [ModelEntry] {
        var entries: [ModelEntry] = []
        if let shared = sharedFolder { entries += models(in: shared) }
        // Downloaded in Cynapse itself: <org>--<name> folders.
        for folder in (try? FileManager.default.contentsOfDirectory(at: ModelDownloader.folder, includingPropertiesForKeys: nil)) ?? []
            where isModelFolder(folder) {
            entries.append(ModelEntry(kind: .local(path: folder.path), name: folder.lastPathComponent.replacingOccurrences(of: "--", with: "/")))
        }
        for folder in addedFolders() { entries += models(in: folder) }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), AppleModel.availability.available {
            entries.append(ModelEntry(kind: .apple, name: "Apple Intelligence"))
        }
        #endif
        entries += cloudModels()
        var seen = Set<String>()
        return entries.filter { seen.insert($0.id).inserted }
    }

    /// The model, ready to be asked. Throws when a cloud key is missing.
    static func model(for entry: ModelEntry, fingerprint: (hash: String, size: Int64)?) throws -> any CheckedModel {
        switch entry.kind {
        case .local(let path):
            return MLXModel(folder: URL(fileURLWithPath: path), name: entry.name, fingerprint: fingerprint)
        case .apple:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) { return AppleModel() }
            #endif
            throw LibraryError.unavailable("Apple Intelligence needs macOS 26 or later.")
        case .cloud(let provider, let model):
            guard let key = Keychain.key(for: provider), !key.isEmpty else {
                throw LibraryError.unavailable("Add your \(provider.displayName) key in Settings first.")
            }
            return CloudModel(provider: provider, model: model, key: key)
        }
    }

    enum LibraryError: LocalizedError {
        case unavailable(String)
        var errorDescription: String? { if case .unavailable(let s) = self { s } else { nil } }
    }
}
