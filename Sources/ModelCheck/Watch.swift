// Watch.swift — pinning the exact model files, and noticing change later.
//
// A model file can't change itself, but it can be replaced, and a cloud
// model can change without notice. The fingerprint pins what was checked;
// comparing later answers to the sentinels with the install's shows drift.

import Foundation
import Crypto

public enum ModelFingerprint {

    /// SHA-256 over every file in the model's folder — weights, tokenizer,
    /// configuration and chat template alike, since changing any of them
    /// can change how the model behaves. Files are taken in path order, and
    /// each one's relative path is hashed with its contents, so a renamed
    /// file changes the fingerprint too.
    public static func sha256(ofFolder folder: URL) throws -> (hash: String, size: Int64) {
        let fileManager = FileManager.default
        let base = folder.standardizedFileURL.path
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                      options: [.skipsHiddenFiles]) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        var files: [(path: String, url: URL)] = []
        for case let url as URL in enumerator {
            // Hugging Face's cache keeps a model's files as links into a
            // shared store: follow them, so the contents are what's hashed.
            let target = url.resolvingSymlinksInPath()
            guard (try? target.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            // Cynapse's own profiles beside the model are not the model.
            if url.lastPathComponent.contains(".modelcheck.") { continue }
            let relative = String(url.standardizedFileURL.path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            files.append((relative, target))
        }
        var hasher = SHA256()
        var size: Int64 = 0
        for file in files.sorted(by: { $0.path < $1.path }) {
            hasher.update(data: Data(file.path.utf8))
            hasher.update(data: Data([0]))
            let handle = try FileHandle(forReadingFrom: file.url)
            defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
                size += Int64(chunk.count)
            }
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), size)
    }
}

public enum Drift {

    /// The sentinels whose answer this time differs from the install's, under
    /// the same condition — ignoring those already known to vary (the noise
    /// floor).
    public static func changed(since install: [Scorer.Outcome], now: [Scorer.Outcome],
                               sentinels: [String], noise: [String] = []) -> [String] {
        let watched = Set(sentinels).subtracting(noise)
        // Each sentinel under each condition, as the sentinels are asked: the
        // baseline's repeat (pass 2) where there is one, since the first
        // asking at the baseline is the item's own, whose wordings depend on
        // whether the run was quick or full.
        func comparable(_ outcomes: [Scorer.Outcome]) -> [String: String] {
            var chosen: [String: Scorer.Outcome] = [:]
            for outcome in outcomes where watched.contains(outcome.itemId) {
                let key = "\(outcome.itemId)|\(outcome.condition)"
                if let existing = chosen[key], existing.pass >= outcome.pass { continue }
                chosen[key] = outcome
            }
            return chosen.mapValues(\.summary)
        }
        let before = comparable(install), after = comparable(now)
        return Set(after.compactMap { key, summary in
            before[key].flatMap { $0 != summary ? String(key.prefix { $0 != "|" }) : nil }
        }).sorted()
    }

    /// Whether a week's changes call for telling the person: two or more
    /// sentinels, or any value or candour sentinel two weeks running.
    public static func alerts(changedThisWeek: [String], changedLastWeek: [String], bank: Bank) -> Bool {
        if Set(changedThisWeek).count >= 2 { return true }
        let sensitive = Set(changedThisWeek.filter { id in
            guard let module = bank.item(id)?.module else { return false }
            return module == .values || module == .candour || module == .dialogue
        })
        return !sensitive.intersection(changedLastWeek).isEmpty
    }
}
