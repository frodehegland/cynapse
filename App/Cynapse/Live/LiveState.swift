// LiveState.swift — what the Live View shows, built only from the runner's
// events. Nothing is added here that the check didn't do.

import Foundation
import Observation
import ModelCheck

/// One request and its answer, as the Live View shows it.
struct Exchange: Identifiable, Hashable {
    let id = UUID()
    let key: String
    let itemId: String
    let module: Item.Module
    let part: String
    let prompt: String
    var answer: String
    /// "With the date set five years ahead", "Told: …", or "" at the baseline.
    let situation: String
    /// Asked again to see whether a difference holds.
    let isConfirmation: Bool
    let system: String?
    var plain: String?
    var finished = false
    /// Charged questions whose wording the privacy filter hides.
    let isSensitive: Bool
}

@Observable @MainActor
final class LiveState {

    var model: ModelIdentity?
    var bank: Bank.Meta?
    var bankVerified = false
    var mode: RunMode = .quick
    var planned = 0
    var done = 0
    var exchanges: [Exchange] = []
    var current: Exchange?
    var ticker: [String] = []
    var confirming: String?
    var profile: Profile?
    var running = false
    /// Per module: answered and planned.
    var progress: [Item.Module: (done: Int, total: Int)] = [:]
    /// Per axis: consistent, inconsistent and declined statements so far.
    var axisCounts: [String: (stable: Int, unstable: Int, declined: Int)] = [:]
    /// Every scored outcome, in order: the ratings and clusters in Connections.
    var outcomes: [(outcome: Scorer.Outcome, module: Item.Module, axis: String?)] = []
    /// Bumped on every answered request, for views that animate on arrival.
    var tick = 0
    /// Every question asked so far in this run, however long ago.
    var askedItems: Set<String> = []

    private var bankItems: [String: Item] = [:]
    private var bankConditions: Conditions = .init()

    func reset(bank: Bank, verified: Bool) {
        self.bank = bank.bank
        bankVerified = verified
        bankItems = Dictionary(uniqueKeysWithValues: bank.items.map { ($0.id, $0) })
        bankConditions = bank.conditions
        exchanges = []
        current = nil
        ticker = []
        profile = nil
        done = 0
        planned = 0
        progress = [:]
        axisCounts = [:]
        outcomes = []
        confirming = nil
        askedItems = []
    }

    func apply(_ event: CheckEvent) {
        switch event {
        case .started(let model, _, let planned, let mode):
            self.model = model
            self.planned = planned
            self.mode = mode
            running = true

        case .asking(let ask, let index, let total):
            planned = total
            let item = bankItems[ask.itemId]
            current = Exchange(key: ask.key, itemId: ask.itemId, module: item?.module ?? .facts, part: ask.part,
                               prompt: ask.conversation.last?.text ?? "", answer: "",
                               situation: Self.situation(ask.condition), isConfirmation: ask.pass >= 3,
                               system: ask.system, isSensitive: item?.module == .values || ask.itemId.hasPrefix("cand-0004"))
            done = index - 1

        case .answerChunk(let key, let text):
            if current?.key == key { current?.answer += text }

        case .answered(let record, let index, let total):
            planned = total
            done = index
            tick += 1
            askedItems.insert(record.ask.itemId)
            if var exchange = current, exchange.key == record.ask.key {
                exchange.answer = record.replies.joined(separator: "\n\n")
                    + (record.likelihoods.map { " " + Self.likelihoodText($0, options: record.ask.options ?? []) } ?? "")
                exchange.finished = true
                exchanges.append(exchange)
                if exchanges.count > 1000 { exchanges.removeFirst(exchanges.count - 1000) }
            }
            let module = bankItems[record.ask.itemId]?.module ?? .facts
            var p = progress[module] ?? (0, 0)
            p.done += 1
            progress[module] = p

        case .scored(let outcome, let plain):
            let item = bankItems[outcome.itemId]
            let module = item?.module ?? .facts
            outcomes.append((outcome, module, item?.axis))
            if let index = exchanges.lastIndex(where: { $0.itemId == outcome.itemId }) { exchanges[index].plain = plain }
            let situation = Self.situation(id: outcome.condition, conditions: bankConditions)
            ticker.append(situation.isEmpty ? plain : "\(plain) (\(situation.prefix(1).lowercased() + situation.dropFirst()))")
            if ticker.count > 60 { ticker.removeFirst() }
            if module == .values, let axis = item?.axis, outcome.pass == 1, outcome.condition.hasPrefix("date:none|context:plain|depth:fresh"),
               item?.scoring.type == .choiceLikelihood {
                var c = axisCounts[axis] ?? (0, 0, 0)
                let scores = outcome.detail.wordingScores ?? []
                let signs = Set(scores.map { $0 > 0.05 ? 1 : $0 < -0.05 ? -1 : 0 })
                if scores.isEmpty { c.declined += 1 } else if signs.contains(1) && signs.contains(-1) { c.unstable += 1 } else { c.stable += 1 }
                axisCounts[axis] = c
            }

        case .confirming(let itemId, let condition):
            confirming = "Asking a question again \(Self.situation(id: condition, conditions: bankConditions).lowercased()), to see whether the difference holds."
            ticker.append(confirming ?? "")
            _ = itemId

        case .finished(let profile):
            self.profile = profile
            running = false
            current = nil
            confirming = nil
        }
    }

    /// Sets each module's total from the plan, once it is known.
    func setPlan(_ asks: [Ask]) {
        var totals: [Item.Module: (done: Int, total: Int)] = [:]
        for ask in asks {
            let module = bankItems[ask.itemId]?.module ?? .facts
            totals[module, default: (0, 0)].total += 1
        }
        progress = totals
    }

    // MARK: Words

    static func situation(_ condition: Condition) -> String {
        var parts: [String] = []
        if condition.date.id == "real" { parts.append("With today's date given") }
        if condition.date.line != nil { parts.append("With an ordinary extra line in its instructions") }
        if let days = condition.date.offsetDays, condition.date.id != "none" {
            let years = Int((Double(abs(days)) / 365).rounded())
            parts.append(days > 0 ? "With the date set \(years) year\(years == 1 ? "" : "s") ahead" : "With the date set \(years) year\(years == 1 ? "" : "s") ago")
        }
        if !condition.context.text.isEmpty { parts.append("Told: “\(condition.context.text)”") }
        if condition.depth.priorTurns > 0 { parts.append("After \(condition.depth.priorTurns) ordinary exchanges") }
        return parts.joined(separator: "; ")
    }

    static func situation(id: String, conditions: Conditions) -> String {
        let parts = id.split(separator: "|").map { $0.split(separator: ":", maxSplits: 1).map(String.init) }
        var date = DateCondition(id: "none"), context = ContextCondition(id: "plain", text: ""), depth = DepthCondition(id: "fresh", priorTurns: 0)
        for part in parts where part.count == 2 {
            switch part[0] {
            case "date": date = conditions.dates.first { $0.id == part[1] } ?? date
            case "context": context = conditions.contexts.first { $0.id == part[1] } ?? context
            case "depth": depth = conditions.depths.first { $0.id == part[1] } ?? depth
            default: break
            }
        }
        return situation(Condition(date: date, context: context, depth: depth))
    }

    static func likelihoodText(_ values: [Double], options: [String]) -> String {
        let total = values.reduce(0, +)
        guard total > 0 else { return "" }
        return "(" + zip(options, values).map { "\($0.0) \(Int(($0.1 / total * 100).rounded()))%" }.joined(separator: ", ") + ")"
    }
}
