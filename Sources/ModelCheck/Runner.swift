// Runner.swift — asks the model everything in the plan, one request at a
// time, writing each answer to the transcript as it comes.
//
// The transcript (JSON Lines) is the record of the run: every prompt exactly
// as sent and every answer exactly as given. The profile is worked out from
// it afterwards, so a run that was interrupted resumes from the last answer,
// and anyone can re-score a published transcript themselves.

import Foundation

public enum RunMode: String, Codable, Sendable {
    /// At install: every item in its first wording, the sentinels twice for
    /// the noise floor, and under a far-future date and one context.
    case quick
    /// In the background: every wording, and the sentinels under every
    /// date, context and depth the bank lists.
    case full
}

/// One answered ask.
public struct Record: Codable, Sendable {
    public var ask: Ask
    /// The reply; for a ladder, one reply per step, the opening first.
    public var replies: [String]
    public var likelihoods: [Double]?
    /// "likelihood" or "generated".
    public var method: String
    public var seconds: Double
}

public final class Runner {

    public let bank: Bank
    public let model: any CheckedModel
    public let style: PromptStyle
    /// Where the transcript is written; nil keeps it in memory only.
    public let transcriptURL: URL?
    /// The real date the date conditions are counted from.
    public let now: Date
    /// Told of everything as it happens — for the Live View.
    public var onEvent: ((CheckEvent) -> Void)?
    /// How many times a changed answer is asked again, under the baseline
    /// and under the condition, before the difference is believed.
    public var confirmations = 3

    public init(bank: Bank, model: any CheckedModel, style: PromptStyle = .standard,
                transcriptURL: URL? = nil, now: Date = Date()) {
        self.bank = bank
        self.model = model
        self.style = style
        self.transcriptURL = transcriptURL
        self.now = now
    }

    // MARK: Plan

    /// The baseline: no date stated, no extra context, a fresh conversation.
    public var baseline: Condition {
        let c = bank.conditions
        return Condition(date: c.dates.first { $0.id == "none" } ?? c.dates.first ?? .init(id: "none"),
                         context: c.contexts.first { $0.text.isEmpty } ?? c.contexts.first ?? .init(id: "plain", text: ""),
                         depth: c.depths.first { $0.priorTurns == 0 } ?? c.depths.first ?? .init(id: "fresh", priorTurns: 0))
    }

    /// The conditions the sentinels are asked under besides the baseline:
    /// one thing changed at a time.
    public func variedConditions(_ mode: RunMode) -> [Condition] {
        let base = baseline
        let c = bank.conditions
        let dates = c.dates.filter { $0 != base.date }.map { Condition(date: $0, context: base.context, depth: base.depth) }
        let contexts = c.contexts.filter { $0 != base.context }.map { Condition(date: base.date, context: $0, depth: base.depth) }
        let depths = c.depths.filter { $0 != base.depth }.map { Condition(date: base.date, context: base.context, depth: $0) }
        switch mode {
        case .full:
            return dates + contexts + depths
        case .quick:
            // The furthest date ahead, the first opposed pair of contexts,
            // and the first neutral control to measure them against.
            let realDates = dates.filter { !$0.date.id.hasPrefix("control-") }
            let far = realDates.max { ($0.date.offsetDays ?? 0) < ($1.date.offsetDays ?? 0) }
            let dateControl = dates.first { $0.date.id.hasPrefix("control-") }
            let named = contexts.filter { !$0.context.id.hasPrefix("control-") }
            let control = contexts.first { $0.context.id.hasPrefix("control-") }
            return [far, dateControl].compactMap { $0 } + Array(named.prefix(2)) + [control].compactMap { $0 }
        }
    }

    /// Every ask the run will make, in order.
    public func plan(_ mode: RunMode, likelihoods: Bool) throws -> [Ask] {
        let base = baseline
        var asks: [Ask] = []
        for item in bank.items {
            // A ladder is long; the quick check leaves it for the full run.
            if mode == .quick, item.module == .dialogue { continue }
            asks += try AskBuilder.asks(for: item, in: bank, condition: base, style: style,
                                        allWordings: mode == .full, likelihoods: likelihoods, now: now)
        }
        for id in bank.sentinels {
            guard let item = bank.item(id) else { continue }
            // The same again, unchanged: any difference is noise.
            asks += try AskBuilder.asks(for: item, in: bank, condition: base, style: style,
                                        allWordings: false, likelihoods: likelihoods, now: now)
                .map { var a = $0; a.pass = 2; return a }
            for condition in variedConditions(mode) {
                asks += try AskBuilder.asks(for: item, in: bank, condition: condition, style: style,
                                            allWordings: false, likelihoods: likelihoods, now: now)
            }
        }
        return asks
    }

    // MARK: Run

    /// Runs the plan, skipping what the transcript already holds; then asks
    /// again any sentinel whose answer changed under a condition, to see
    /// whether the difference holds. `progress` is told after each answer.
    public func run(_ mode: RunMode, progress: ((Int, Int, Record) -> Void)? = nil) async throws -> [Record] {
        // Whether the model can score options, found by asking once.
        let likelihoods = (try? await model.likelihoods(system: nil, conversation: [Turn(.user, "Is the sky blue?")],
                                                        options: ["Yes", "No"])) != nil
        var asks = try plan(mode, likelihoods: likelihoods)

        let problems = PromptLint.problems(in: asks)
        if !problems.isEmpty { throw RunFailure.lint(problems) }

        onEvent?(.started(model: model.identity, bank: bank.bank, planned: asks.count, mode: mode))
        var records = Self.readTranscript(transcriptURL)
        try await ask(asks, into: &records, progress: progress)

        // Confirmation: a changed answer is asked again before it counts.
        let confirm = try confirmationAsks(records: records, likelihoods: likelihoods)
        if !confirm.isEmpty {
            asks += confirm
            try await ask(confirm, into: &records, progress: progress)
        }

        let order = Dictionary(asks.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { a, _ in a })
        return records.filter { order[$0.ask.key] != nil }.sorted { order[$0.ask.key]! < order[$1.ask.key]! }
    }

    /// Runs and returns the profile, telling `onEvent` it is finished.
    public func check(_ mode: RunMode, createdAt: Date = Date()) async throws -> Profile {
        let records = try await run(mode)
        let profile = ProfileBuilder.build(records: records, bank: bank, model: model.identity, mode: mode,
                                           baseline: baseline, createdAt: createdAt)
        onEvent?(.finished(profile))
        return profile
    }

    func ask(_ asks: [Ask], into records: inout [Record], progress: ((Int, Int, Record) -> Void)?) async throws {
        let done = Set(records.map(\.ask.key))
        // How many asks make up each item under each condition, so an item
        // can be scored the moment its last part is answered.
        let groupSizes = Dictionary(grouping: asks) { Self.group($0) }.mapValues(\.count)
        var answered = Dictionary(grouping: records) { Self.group($0.ask) }
        let total = asks.count
        for (index, ask) in asks.enumerated() where !done.contains(ask.key) {
            try Task.checkCancellation()
            onEvent?(.asking(ask, index: index + 1, of: total))
            let record = try await answer(ask)
            records.append(record)
            try append(record)
            onEvent?(.answered(record, index: index + 1, of: total))
            progress?(index + 1, total, record)

            let group = Self.group(ask)
            answered[group, default: []].append(record)
            if answered[group]?.count == groupSizes[group], let item = bank.item(ask.itemId),
               let outcome = Scorer.outcome(item, answered[group]!.sorted { $0.ask.part < $1.ask.part }, bank: bank) {
                onEvent?(.scored(outcome, plain: outcome.plainText(item: item)))
            }
        }
    }

    static func group(_ ask: Ask) -> String { "\(ask.itemId)|\(ask.condition.id)|\(ask.pass)" }

    /// For each sentinel whose answer under a condition differs from the
    /// baseline's, the same asks again — `confirmations` times under each.
    func confirmationAsks(records: [Record], likelihoods: Bool) throws -> [Ask] {
        guard confirmations > 0 else { return [] }
        let outcomes = Scorer.outcomes(records, bank: bank)
        let base = baseline
        let baseSummaries = Dictionary(outcomes.filter { $0.condition == base.id && $0.pass == 2 }.map { ($0.itemId, $0.summary) },
                                       uniquingKeysWith: { a, _ in a })
        var asks: [Ask] = []
        for outcome in outcomes where outcome.pass == 1 && outcome.condition != base.id && bank.sentinels.contains(outcome.itemId) {
            guard let before = baseSummaries[outcome.itemId], before != outcome.summary,
                  let item = bank.item(outcome.itemId),
                  let condition = records.first(where: { $0.ask.itemId == outcome.itemId && $0.ask.condition.id == outcome.condition })?.ask.condition
            else { continue }
            onEvent?(.confirming(itemId: outcome.itemId, condition: outcome.condition))
            for pass in 3..<(3 + confirmations) {
                for c in [base, condition] {
                    asks += try AskBuilder.asks(for: item, in: bank, condition: c, style: style,
                                                allWordings: false, likelihoods: likelihoods, now: now)
                        .map { var a = $0; a.pass = pass; return a }
                }
            }
        }
        // The baseline re-asks are shared by every condition of the same item.
        var seen = Set<String>()
        return asks.filter { seen.insert($0.key).inserted }
    }

    func answer(_ ask: Ask) async throws -> Record {
        let started = Date()
        if let options = ask.options,
           let scores = try await model.likelihoods(system: ask.system, conversation: ask.conversation, options: options) {
            return Record(ask: ask, replies: [], likelihoods: scores, method: "likelihood",
                          seconds: Date().timeIntervalSince(started))
        }
        var conversation = ask.conversation
        var replies: [String] = []
        let key = ask.key
        let onEvent = self.onEvent
        for followUp in [nil] + (ask.followUps ?? []).map(Optional.some) {
            if let followUp { conversation.append(Turn(.user, followUp)) }
            var reply: String
            do {
                if let streaming = model as? any StreamingCheckedModel {
                    reply = try await streaming.reply(system: ask.system, conversation: conversation) { chunk in
                        onEvent?(.answerChunk(key: key, text: chunk))
                    }
                } else {
                    reply = try await model.reply(system: ask.system, conversation: conversation)
                }
            } catch let refusal as ModelRefusal {
                // Worded so the scoring reads it as the refusal it is.
                reply = "I can't answer that. [Declined by the model's safety system: \(refusal.message)]"
            }
            replies.append(reply)
            conversation.append(Turn(.assistant, reply))
        }
        return Record(ask: ask, replies: replies, likelihoods: nil, method: "generated",
                      seconds: Date().timeIntervalSince(started))
    }

    // MARK: Transcript

    func append(_ record: Record) throws {
        guard let url = transcriptURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(record)
        line.append(0x0A)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }

    public static func readTranscript(_ url: URL?) -> [Record] {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { try? decoder.decode(Record.self, from: Data($0.utf8)) }
    }
}

public enum RunFailure: Error, CustomStringConvertible {
    case lint([PromptLint.Problem])
    public var description: String {
        switch self {
        case .lint(let problems):
            "Some prompts would tell the model it is being checked, so nothing was sent:\n"
                + problems.map { "  " + $0.description }.joined(separator: "\n")
        }
    }
}
