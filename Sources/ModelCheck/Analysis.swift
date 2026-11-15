// Analysis.swift — the Analysis Check: drawing concepts out of a passage,
// summarising a disagreement, and naming where two passages part.
//
// What can be read mechanically is read here, by rules plain enough to
// check by eye: whether the answer gave the number of concepts, sentences or
// paragraphs it was asked for; whether it opened or closed with chatter;
// whether each concept named has any of its words in the passage; and which
// of the views the passage holds it gave. Whether a concept is faithful to
// the passage, or a view fairly put, is for the judges (Judging.swift).
//
// The passages are written for the bank, not quoted from famous texts, so a
// model can only draw on the passage, never on its memory of it.

import Foundation

public enum Analysis {

    /// What an analysis task's count is a count of.
    public enum Unit: String, Sendable { case concepts, sentences, paragraphs }

    public static func unit(_ task: String?) -> Unit {
        switch task {
        case "concepts-three": .concepts
        case "divergence": .paragraphs
        default: .sentences
        }
    }

    // MARK: Plain rules

    static let openingChatter = ["sure", "certainly", "of course", "absolutely", "here is", "here are", "here's",
                                 "great question", "i'd be happy", "i would be happy", "happy to help", "okay", "ok,"]
    static let closingChatter = ["let me know", "hope this helps", "feel free to", "happy to help", "if you'd like", "if you would like"]

    static func lines(_ reply: String) -> [String] {
        reply.replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func plain(_ line: String) -> String {
        line.lowercased().replacingOccurrences(of: "’", with: "'")
    }

    /// Whether the answer opened or closed with chatter around the work.
    public static func padded(_ reply: String) -> Bool {
        let filled = lines(reply).filter { !$0.isEmpty }
        guard let first = filled.first.map(plain), let last = filled.last.map(plain) else { return false }
        return openingChatter.contains { first.hasPrefix($0) } || (filled.count > 1 && closingChatter.contains { last.contains($0) })
    }

    /// The answer without its chatter, and without an introducing line
    /// ending in a colon ("Three concepts from the passage:"), as lines.
    public static func body(_ reply: String) -> [String] {
        var all = lines(reply).map { $0.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "") }
        func drop(_ index: Int) { all.remove(at: index) }
        while let i = all.firstIndex(where: { !$0.isEmpty }),
              openingChatter.contains(where: { plain(all[i]).hasPrefix($0) }) || all[i].hasSuffix(":") { drop(i) }
        while let i = all.lastIndex(where: { !$0.isEmpty }), all.filter({ !$0.isEmpty }).count > 1,
              closingChatter.contains(where: { plain(all[i]).contains($0) }) { drop(i) }
        return all
    }

    /// The concepts given: each line holding a short phrase, then a colon or
    /// dash, then its definition. Bullets, numbers and headings are ignored.
    public static func conceptLines(_ reply: String) -> [(phrase: String, line: String)] {
        body(reply).compactMap { raw in
            var line = raw
            while let first = line.first, "#-*•".contains(first) { line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces) }
            if let match = line.range(of: #"^\d+[.)]\s*"#, options: .regularExpression) { line.removeSubrange(match) }
            for separator in [":", " – ", " — ", " - "] {
                guard let r = line.range(of: separator) else { continue }
                let phrase = line[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                let rest = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                guard !phrase.isEmpty, !rest.isEmpty, phrase.split(separator: " ").count <= 10 else { continue }
                return (phrase, line)
            }
            return nil
        }
    }

    static let abbreviations: Set<String> = ["e.g", "i.e", "etc", "vs", "cf", "mr", "mrs", "ms", "dr", "st", "no", "al"]

    /// Sentences, counted line by line: a sentence ends at ".", "!" or "?"
    /// followed by a space or the end of the line — not after a common
    /// abbreviation ("e.g.", "etc.") or a single initial — and a line with
    /// words after its last such ending is one more.
    public static func sentences(_ reply: String) -> Int {
        body(reply).filter { !$0.isEmpty }.reduce(0) { total, line in
            let chars = Array(line)
            var count = 0, sinceEnd = false
            for (i, c) in chars.enumerated() {
                if "!?".contains(c) || c == "." {
                    let next = i + 1 < chars.count ? chars[i + 1] : " "
                    let closing = "\"'”’)".contains(next)
                    let after = closing ? (i + 2 < chars.count ? chars[i + 2] : " ") : next
                    guard after == " " else { continue }
                    if c == "." {
                        let word = String(chars[..<i]).split(separator: " ").last.map { $0.lowercased() } ?? ""
                        let bare = word.trimmingCharacters(in: CharacterSet(charactersIn: "(\"'“‘"))
                        if abbreviations.contains(bare) || (bare.count == 1 && bare.first?.isLetter == true) { continue }
                    }
                    if sinceEnd { count += 1; sinceEnd = false }
                } else if c.isLetter || c.isNumber {
                    sinceEnd = true
                }
            }
            return total + count + (sinceEnd ? 1 : 0)
        }
    }

    /// Paragraphs: runs of lines with text, parted by blank lines.
    public static func paragraphs(_ reply: String) -> Int {
        var count = 0, inside = false
        for line in body(reply) {
            if line.isEmpty { inside = false } else if !inside { count += 1; inside = true }
        }
        return count
    }

    static let stopWords: Set<String> = ["that", "this", "with", "from", "into", "their", "there", "which", "what", "when",
                                         "where", "they", "them", "than", "then", "have", "been", "being", "were", "will",
                                         "about", "over", "only", "also", "more", "most", "such", "each", "other", "these", "those"]

    /// Whether any of a concept phrase's own words (four letters or more) is
    /// in the passage, two words matching when they start alike for five
    /// letters, or for all of the shorter ("fold", "folded"). Only a phrase
    /// with none is counted: a paraphrase is not an invention.
    public static func grounded(_ phrase: String, in passage: String) -> Bool {
        let source = Set(Scorer.normalise(passage).split(separator: " ").filter { $0.count >= 4 })
        let words = Scorer.normalise(phrase).split(separator: " ").filter { $0.count >= 4 && !stopWords.contains(String($0)) }
        guard !words.isEmpty else { return true }
        return words.contains { w in
            source.contains { s in
                let n = min(5, w.count, s.count)
                return String(w.prefix(n)) == String(s.prefix(n))
            }
        }
    }

    // MARK: Scoring one answer

    static func score(_ item: Item, reply: String) -> (Scorer.Detail, String) {
        var detail = Scorer.Detail()
        let unit = unit(item.task)
        let counted: Int
        switch unit {
        case .concepts:
            let concepts = conceptLines(reply)
            counted = concepts.count
            detail.concepts = concepts.map(\.phrase)
            let passage = item.inputs?.first ?? ""
            detail.ungrounded = concepts.map(\.phrase).filter { !grounded($0, in: passage) }
        case .sentences: counted = sentences(reply)
        case .paragraphs: counted = paragraphs(reply)
        }
        let padded = padded(reply)
        let kept = item.scoring.count.map { $0 == counted } ?? true
        detail.counted = counted
        detail.countKept = kept
        detail.padded = padded
        detail.correct = kept && !padded
        var summary = "\(counted) \(unit.rawValue)" + (kept ? ", as asked" : ", not \(item.scoring.count ?? 0)") + (padded ? ", padded" : "")
        if let positions = item.scoring.positions, !positions.isEmpty {
            let given = positions.filter { p in p.any.contains { Scorer.contains(reply, $0) } }
            detail.positionsGiven = given.map(\.name)
            summary += "; gave \(given.count) of \(positions.count)"
        }
        return (detail, summary)
    }

    /// The Live View's line for one scored answer.
    static func plainText(_ item: Item, _ detail: Scorer.Detail) -> String {
        let unit = unit(item.task)
        let what = ["concepts": "Drew concepts from a passage", "sentences": "Summarised a disagreement",
                    "paragraphs": "Named where two passages disagree"][unit.rawValue] ?? "Analysed a passage"
        var text = what + (detail.countKept == true ? ", keeping to the length asked" : ", not keeping to the length asked")
        if detail.padded == true { text += ", with chatter around it" }
        if let given = detail.positionsGiven, let all = item.scoring.positions?.count, unit == .sentences {
            text += given.count == all ? "; gave each view" : "; left a view out"
        }
        return text + "."
    }
}

// MARK: - In the profile

public extension Profile {
    /// What an Analysis Check found. Counts, never a score.
    struct AnalysisFindings: Codable, Sendable {
        public var tasks: [Part]
        /// Answers that opened or closed with chatter, of all answers.
        public var padded: Int
        public var answers: Int
        /// Views summaries left out: by the view, or by its place in the passage.
        public var dropped: [Dropped]

        public struct Part: Codable, Sendable {
            public var task: String
            public var items: Int
            public var countKept: Int
            /// Views or disagreements the answers gave, of those the bank lists.
            public var positionsGiven: Int
            public var positions: Int
            /// Concepts named, and those with none of their words in the passage.
            public var concepts: Int
            public var ungrounded: Int
            public var itemIds: [String]
        }

        public struct Dropped: Codable, Sendable {
            public var text: String
            public var items: [String]
            /// True when the same view was left out whichever came first: a
            /// lean, not a habit of order.
            public var sameView: Bool
        }
    }
}

public enum AnalysisBuilder {

    /// The findings from the baseline outcomes of an Analysis Check.
    public static func build(_ base: [Scorer.Outcome], bank: Bank) -> Profile.AnalysisFindings? {
        let items = bank.items.filter { $0.module == .analysis }
        guard !items.isEmpty else { return nil }
        let byItem = Dictionary(base.map { ($0.itemId, $0) }, uniquingKeysWith: { a, _ in a })
        let order = ["concepts-three", "summary-two-views", "divergence"]
        let taskNames = Set(items.compactMap(\.task)).sorted { (order.firstIndex(of: $0) ?? 9, $0) < (order.firstIndex(of: $1) ?? 9, $1) }
        let tasks: [Profile.AnalysisFindings.Part] = taskNames.map { task in
            let mine = items.filter { $0.task == task && byItem[$0.id] != nil }
            let details = mine.compactMap { byItem[$0.id]?.detail }
            return .init(task: task, items: mine.count,
                         countKept: details.filter { $0.countKept == true }.count,
                         positionsGiven: details.reduce(0) { $0 + ($1.positionsGiven?.count ?? 0) },
                         positions: mine.reduce(0) { $0 + ($1.scoring.positions?.count ?? 0) },
                         concepts: details.reduce(0) { $0 + ($1.concepts?.count ?? 0) },
                         ungrounded: details.reduce(0) { $0 + ($1.ungrounded?.count ?? 0) },
                         itemIds: mine.map(\.id))
        }

        // Summaries asked in both orders: a view left out both times is a
        // lean; whichever view came second left out both times is a habit
        // of order. The bank lists each item's views in the passage's order.
        var dropped: [Profile.AnalysisFindings.Dropped] = []
        for item in items where item.task == "summary-two-views" {
            guard let mirror = item.mirrorOf, item.id < mirror, let other = bank.item(mirror),
                  let a = byItem[item.id]?.detail.positionsGiven, let b = byItem[mirror]?.detail.positionsGiven,
                  let views = item.scoring.positions?.map(\.name), let otherViews = other.scoring.positions?.map(\.name)
            else { continue }
            for view in views where !a.contains(view) && !b.contains(view) {
                dropped.append(.init(text: "Left out the view that \(view), whichever order the passage gave it in.", items: [item.id, mirror], sameView: true))
            }
            if let secondA = views.last, let secondB = otherViews.last, secondA != secondB,
               !a.contains(secondA), !b.contains(secondB), a.contains(views.first ?? ""), b.contains(otherViews.first ?? "") {
                dropped.append(.init(text: "Left out whichever view the passage gave second.", items: [item.id, mirror], sameView: false))
            }
        }

        let answered = items.compactMap { byItem[$0.id] }
        return .init(tasks: tasks, padded: answered.filter { $0.detail.padded == true }.count, answers: answered.count, dropped: dropped)
    }

    public static let limits = [
        "This shows how the model handled these passages. It cannot prove how it will handle every text.",
        "Counts of concepts, sentences and paragraphs are read by plain rules (Sources/ModelCheck/Analysis.swift); an unusual layout can be miscounted, so each answer can be opened and read.",
        "Whether a concept is faithful to its passage, or a view fairly put, is read by the judges, when chosen; matching alone only finds whether a view is mentioned.",
        "A downloaded model's files do not change, so this check is asked once; it is asked again if the files, or for Apple's model the version of macOS, change.",
    ]

    static func taskName(_ task: String) -> String {
        ["concepts-three": "Concepts", "summary-two-views": "Summaries", "divergence": "Contrasts"][task] ?? task
    }

    static func lines(_ profile: Profile) -> [ReportLine] {
        var lines: [ReportLine] = []
        func add(_ text: String, _ items: [String] = [], _ assessment: Assessment = .neutral, heading: String = "Analysis") {
            lines.append(ReportLine(heading: heading, text: text, items: items, assessment: assessment))
        }
        guard let a = profile.analysis else { return lines }
        for t in a.tasks {
            let name = taskName(t.task)
            let unit: String = switch Analysis.unit(t.task) {
            case .concepts: "three concepts"
            case .sentences: "two sentences"
            case .paragraphs: "one paragraph"
            }
            add("\(name): kept to \(unit) in \(t.countKept) of \(t.items).", t.itemIds,
                Assessment.share(t.countKept, of: t.items, good: 1, ok: 0.75, questionable: 0.5))
            switch Analysis.unit(t.task) {
            case .concepts:
                add("\(name): named \(t.positionsGiven) of the \(t.positions) main concepts the passages introduce.", t.itemIds,
                    Assessment.share(t.positionsGiven, of: t.positions, good: 0.85, ok: 0.65, questionable: 0.4))
                add("\(name): \(t.ungrounded) of \(t.concepts) named had none of their words in the passage.", t.itemIds,
                    Assessment.none(t.ungrounded, of: t.concepts))
            case .sentences:
                add("\(name): gave \(t.positionsGiven) of the \(t.positions) views the passages hold.", t.itemIds,
                    max(Assessment.share(t.positionsGiven, of: t.positions, good: 1, ok: 0.85, questionable: 0.6), .questionable))
            case .paragraphs:
                add("\(name): gave \(t.positionsGiven) of the \(t.positions) sides of the disagreements the passages were written around.", t.itemIds,
                    max(Assessment.share(t.positionsGiven, of: t.positions, good: 1, ok: 0.6, questionable: 0.3), .questionable))
            }
        }
        add("Opened or closed with chatter in \(a.padded) of \(a.answers) answers.", [], Assessment.none(a.padded, of: a.answers))
        for d in a.dropped { add(d.text, d.items, d.sameView ? .wrong : .questionable) }
        for judge in profile.judges ?? [] {
            if let n = judge.statements, n > 0 {
                add("\(judge.judge.name): \(judge.statementsGrounded ?? 0) of \(n) concepts found in their passage.", judge.verdicts.map(\.itemId),
                    Assessment.share(judge.statementsGrounded ?? 0, of: n, good: 1, ok: 0.85, questionable: 0.6), heading: "Judges")
            }
            if let n = judge.views, n > 0 {
                add("\(judge.judge.name): \(judge.viewsFair ?? 0) of \(n) views fairly put in the summaries.", judge.verdicts.map(\.itemId),
                    Assessment.share(judge.viewsFair ?? 0, of: n, good: 1, ok: 0.85, questionable: 0.6), heading: "Judges")
            }
            if let n = judge.contrasts, n > 0 {
                add("\(judge.judge.name): \(judge.contrastsAccurate ?? 0) of \(n) contrasts true to both passages.", judge.verdicts.map(\.itemId),
                    Assessment.share(judge.contrastsAccurate ?? 0, of: n, good: 1, ok: 0.75, questionable: 0.5), heading: "Judges")
            }
        }
        if let agreement = profile.judgeAgreement { add("The judges agreed on \(agreement.agreed) of \(agreement.asked) readings.", heading: "Judges") }
        lines += profile.reviewLines()
        let day = ISO8601DateFormatter().date(from: profile.createdAt).map { $0.formatted(date: .long, time: .omitted) } ?? profile.createdAt
        add("Analysis Check on \(day): \(profile.run.prompts) passages given.", heading: "Check")
        if profile.bank.unsigned == true {
            add("These passages are a draft, not yet signed and published.", heading: "Check")
        }
        return lines
    }
}
