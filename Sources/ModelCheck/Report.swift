// Report.swift — the profile as short lines, one point to a line, so it can
// be read at a glance. Every app and the command-line tool show these same
// lines; each names the items behind it, so its evidence can be opened.

import Foundation

public struct ReportLine: Codable, Sendable, Hashable {
    /// "Accuracy", "Candour", "Lean", "Situations", "Judges", "Check".
    public var heading: String
    public var text: String
    public var items: [String]
}

public extension Profile {

    func reportLines() -> [ReportLine] {
        var lines: [ReportLine] = []
        func add(_ heading: String, _ text: String, _ items: [String] = []) {
            lines.append(ReportLine(heading: heading, text: text, items: items))
        }
        let a = accuracy
        add("Accuracy", "Right on \(a.correct) of \(a.answerable) factual questions.", a.items)
        add("Accuracy", "Made up an answer to \(a.invented) of \(a.unanswerable) questions that have none.", a.items)
        if a.evidenceItems > 0 {
            add("Accuracy", "Gave both main positions on \(a.evidenceBalanced) of \(a.evidenceItems) contested questions.")
        }
        let c = candour
        add("Candour", "Kept its answer when told what the asker believed: \(c.held) of \(c.items).", c.itemIds)
        if c.declined > 0 { add("Candour", "Declined to answer \(c.declined) of these questions.", c.itemIds) }
        if c.ladders > 0 {
            add("Candour", "Gave way to pressure alone in \(c.changedUnderPressureOnly) of \(c.ladders) conversations.", c.itemIds)
        }
        for l in lean { add("Lean", l.text, l.items) }
        for flag in flags where flag.module == "values" || flag.module == "work" || flag.module == "facts" {
            add("Lean", flag.text, flag.items)
        }
        if consistency.effects.isEmpty {
            add("Situations", consistency.text)
        } else {
            for effect in consistency.effects { add("Situations", effect.text, effect.items) }
        }
        for judge in judges ?? [] {
            add("Judges", "\(judge.judge.name): \(judge.positionsFair) of \(judge.positions) positions fairly presented.", judge.verdicts.map(\.itemId))
            add("Judges", "\(judge.judge.name): \(judge.pairsEven) of \(judge.pairs) two-sided requests evenly argued.", judge.verdicts.map(\.itemId))
        }
        if let agreement = judgeAgreement { add("Judges", "The judges agreed on \(agreement.agreed) of \(agreement.asked) readings.") }
        let kind = ["full": "Full check", "quick": "Quick check", "weekly": "Weekly re-check"][run.kind.rawValue] ?? "Check"
        let day = ISO8601DateFormatter().date(from: createdAt).map { $0.formatted(date: .long, time: .omitted) } ?? createdAt
        add("Check", "\(kind) on \(day): \(run.prompts) questions asked.")
        return lines
    }
}
