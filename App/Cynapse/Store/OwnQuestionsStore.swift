// OwnQuestionsStore.swift — the person's own questions, written with an
// online AI and pasted in (QuestionWriting). Kept apart from the signed
// bank, in one plain JSON file anyone can read or edit.

import Foundation
import ModelCheck

enum OwnQuestionsStore {

    static var url: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = support.appendingPathComponent("Cynapse", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("My Questions.json")
    }

    static func load() -> [Item] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return ((try? JSONDecoder().decode([Item].self, from: data)) ?? []).filter(\.isOwn)
    }

    static func save(_ items: [Item]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? encoder.encode(items).write(to: url, options: .atomic)
    }
}
