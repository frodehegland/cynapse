// ProfileStore.swift — every profile kept, never overwritten, each with its
// full transcript.
//
// Application Support/Cynapse/Profiles/<model>/
//   <date>.modelcheck.json             the profile
//   <date>.modelcheck.transcript.jsonl every prompt and answer
//   current.transcript.jsonl           a run in progress, for resuming
//
// The newest profile is also copied to the App Group, where Author and
// Knowledge Space can show it.

import Foundation
import ModelCheck

struct StoredProfile: Identifiable, Hashable {
    let url: URL
    var profile: Profile
    var id: URL { url }
    var transcriptURL: URL {
        url.deletingPathExtension().appendingPathExtension("transcript.jsonl")
    }
    var date: Date { ISO8601DateFormatter().date(from: profile.createdAt) ?? .distantPast }

    static func == (a: StoredProfile, b: StoredProfile) -> Bool { a.url == b.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

enum ProfileStore {

    static var root: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Cynapse/Profiles", isDirectory: true)
    }

    static func folder(for entry: ModelEntry) -> URL {
        let url = root.appendingPathComponent(entry.storeKey, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The run in progress; an Analysis Check resumes from its own, so the
    /// two kinds of check never mix their answers.
    static func currentTranscript(for entry: ModelEntry, analysis: Bool = false) -> URL {
        folder(for: entry).appendingPathComponent(analysis ? "current-analysis.transcript.jsonl" : "current.transcript.jsonl")
    }

    /// All of a model's profiles, newest first.
    static func profiles(for entry: ModelEntry) -> [StoredProfile] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder(for: entry), includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasSuffix(".modelcheck.json") }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url), let profile = try? JSONDecoder().decode(Profile.self, from: data) else { return nil }
                return StoredProfile(url: url, profile: profile)
            }
            .sorted { $0.date > $1.date }
    }

    /// Saves a finished run: the profile, and the transcript moved beside it.
    @discardableResult
    static func save(_ incoming: Profile, for entry: ModelEntry, transcript current: URL? = nil) throws -> StoredProfile {
        var profile = incoming
        profile.report = profile.reportLines().map { "\($0.heading): \($0.text)" }
        let stamp = profile.createdAt.replacingOccurrences(of: ":", with: "-")
        let url = folder(for: entry).appendingPathComponent("\(stamp).modelcheck.json")
        try profile.jsonData().write(to: url)
        let stored = StoredProfile(url: url, profile: profile)
        let current = current ?? currentTranscript(for: entry)
        if FileManager.default.fileExists(atPath: current.path) {
            try? FileManager.default.moveItem(at: current, to: stored.transcriptURL)
        }
        if let shared = ModelLibrary.sharedProfilesFolder {
            try? FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
            // Named by the model's name ("org--name"), the name Author and
            // Knowledge Space know it by. An Analysis Check has its own file
            // beside it, so it never replaces the Character Check.
            let suffix = profile.run.kind == .analysis ? "analysis" : "modelcheck"
            try? profile.jsonData().write(to: shared.appendingPathComponent("\(sharedName(entry)).\(suffix).json"))
        }
        return stored
    }

    /// Writes a profile again after something was added to it (a review);
    /// the shared copy too, when it is the newest of its kind.
    static func rewrite(_ profile: Profile, at url: URL, for entry: ModelEntry, shared: Bool) throws {
        try profile.jsonData().write(to: url)
        guard shared, let folder = ModelLibrary.sharedProfilesFolder else { return }
        let suffix = profile.run.kind == .analysis ? "analysis" : "modelcheck"
        try? profile.jsonData().write(to: folder.appendingPathComponent("\(sharedName(entry)).\(suffix).json"))
    }

    static func sharedName(_ entry: ModelEntry) -> String {
        entry.name.replacingOccurrences(of: "/", with: "--")
    }

    static func records(of stored: StoredProfile) -> [Record] {
        Runner.readTranscript(stored.transcriptURL)
    }

    /// The profile and its transcript, copied into a folder the person chose.
    static func export(_ stored: StoredProfile, to folder: URL) throws {
        let fm = FileManager.default
        let name = stored.url.lastPathComponent
        try? fm.removeItem(at: folder.appendingPathComponent(name))
        try fm.copyItem(at: stored.url, to: folder.appendingPathComponent(name))
        if fm.fileExists(atPath: stored.transcriptURL.path) {
            let tname = stored.transcriptURL.lastPathComponent
            try? fm.removeItem(at: folder.appendingPathComponent(tname))
            try fm.copyItem(at: stored.transcriptURL, to: folder.appendingPathComponent(tname))
        }
    }
}
