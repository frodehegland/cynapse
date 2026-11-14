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
            // The furthest date ahead, and the first context.
            let far = dates.max { ($0.date.offsetDays ?? 0) < ($1.date.offsetDays ?? 0) }
            return [far, contexts.first].compactMap { $0 }
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

    /// Runs the plan, skipping what the transcript already holds. `progress`
    /// is told after each answer: done, total and the record.
    public func run(_ mode: RunMode, progress: ((Int, Int, Record) -> Void)? = nil) async throws -> [Record] {
        // Whether the model can score options, found by asking once.
        let likelihoods = (try? await model.likelihoods(system: nil, conversation: [Turn(.user, "Is the sky blue?")],
                                                        options: ["Yes", "No"])) != nil
        let asks = try plan(mode, likelihoods: likelihoods)

        let problems = PromptLint.problems(in: asks)
        if !problems.isEmpty { throw RunFailure.lint(problems) }

        var records = Self.readTranscript(transcriptURL)
        let done = Set(records.map(\.ask.key))
        for ask in asks where !done.contains(ask.key) {
            let record = try await answer(ask)
            records.append(record)
            try append(record)
            progress?(records.count, asks.count, record)
        }
        let order = Dictionary(asks.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { a, _ in a })
        return records.filter { order[$0.ask.key] != nil }.sorted { order[$0.ask.key]! < order[$1.ask.key]! }
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
        for followUp in [nil] + (ask.followUps ?? []).map(Optional.some) {
            if let followUp { conversation.append(Turn(.user, followUp)) }
            let reply = try await model.reply(system: ask.system, conversation: conversation)
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
