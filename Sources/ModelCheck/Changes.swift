// Changes.swift — what changed between two checks of the same kind: each
// question asked plainly in both whose reading differs, with whether it
// rates better, worse, or (for a position, never rated) simply moved.
//
// Only checks of the same kind are compared — quick with quick, full with
// full, Analysis with Analysis — since a full check asks more wordings than a
// quick one, and comparing across them would show changes that aren't there.

import Foundation

public struct ResultChange: Sendable, Hashable, Identifiable {
    public enum Direction: String, Sendable { case better, worse, moved }
    public var itemId: String
    public var id: String { itemId }
    /// The kind of question, in words.
    public var kind: String
    /// How Cynapse read the answer, before and now.
    public var before: String
    public var after: String
    public var beforeAssessment: Assessment
    public var afterAssessment: Assessment
    public var direction: Direction
}

public enum ResultChanges {

    /// Every question asked plainly (no date, no added context, a fresh
    /// conversation, first asking), with its outcome.
    static func plainOutcomes(_ records: [Record], bank: Bank) -> [String: Scorer.Outcome] {
        let plain = records.filter {
            $0.ask.pass == 1 && $0.ask.condition.date.id == "none" && $0.ask.condition.context.text.isEmpty && $0.ask.condition.depth.priorTurns == 0
        }
        return Dictionary(Scorer.outcomes(plain, bank: bank).map { ($0.itemId, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// How many questions both checks asked, and those whose reading changed:
    /// worse first, then moved, then better.
    public static func compare(before: [Record], after: [Record], bank: Bank) -> (compared: Int, changes: [ResultChange]) {
        let was = plainOutcomes(before, bank: bank), now = plainOutcomes(after, bank: bank)
        let shared = Set(was.keys).intersection(now.keys)
        var changes: [ResultChange] = []
        for id in shared.sorted() {
            guard let item = bank.item(id), let a = was[id], let b = now[id], a.summary != b.summary else { continue }
            let ra = a.assessment(item: item), rb = b.assessment(item: item)
            // Assessment sorts worse first; a position is never better or worse.
            let direction: ResultChange.Direction = ra == .neutral || rb == .neutral || ra == rb ? .moved : rb < ra ? .worse : .better
            changes.append(ResultChange(itemId: id, kind: ExternalReviewing.kind(item),
                                        before: a.plainText(item: item) + " [\(a.summary)]",
                                        after: b.plainText(item: item) + " [\(b.summary)]",
                                        beforeAssessment: ra, afterAssessment: rb, direction: direction))
        }
        let order: [ResultChange.Direction: Int] = [.worse: 0, .moved: 1, .better: 2]
        changes.sort { (order[$0.direction]!, $0.itemId) < (order[$1.direction]!, $1.itemId) }
        return (shared.count, changes)
    }
}
