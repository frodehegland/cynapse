// Bank.swift — the question bank: what is asked, and how each answer is scored.
//
// A bank is one JSON file with a detached Ed25519 signature beside it
// (`bank.json.sig`). It is never rewritten by the app, so any field this
// code does not know is kept simply by leaving the file alone.

import Foundation

public struct Bank: Codable, Sendable {
    public var bank: Meta
    public var conditions: Conditions
    /// The fixed items asked under every condition and in every weekly
    /// re-check: the baseline any change is measured against.
    public var sentinels: [String]
    /// Ordinary exchanges asked before an item "at depth", by set name.
    public var fillers: [String: [Turn]]
    /// Balanced lists the context sentences draw from (`<place>`, `<group>`…).
    public var contextLists: [String: [String]]
    /// What each end of an axis stands for, as the bank's authors put it:
    /// a lean is always toward one of these, never "good" or "bad".
    public var axes: [String: AxisPoles]
    public var items: [Item]

    public struct AxisPoles: Codable, Sendable {
        /// The position a score of +1 means.
        public var positive: String
        /// The position a score of −1 means.
        public var negative: String
    }

    public struct Meta: Codable, Sendable {
        public var id: String
        public var version: String
        public var released: String
        public var kind: String
    }

    public init(bank: Meta, conditions: Conditions = .init(), sentinels: [String] = [],
                fillers: [String: [Turn]] = [:], contextLists: [String: [String]] = [:],
                axes: [String: AxisPoles] = [:], items: [Item]) {
        self.bank = bank
        self.conditions = conditions
        self.sentinels = sentinels
        self.fillers = fillers
        self.contextLists = contextLists
        self.axes = axes
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bank = try c.decode(Meta.self, forKey: .bank)
        conditions = try c.decodeIfPresent(Conditions.self, forKey: .conditions) ?? .init()
        sentinels = try c.decodeIfPresent([String].self, forKey: .sentinels) ?? []
        fillers = try c.decodeIfPresent([String: [Turn]].self, forKey: .fillers) ?? [:]
        contextLists = try c.decodeIfPresent([String: [String]].self, forKey: .contextLists) ?? [:]
        axes = try c.decodeIfPresent([String: AxisPoles].self, forKey: .axes) ?? [:]
        items = try c.decode([Item].self, forKey: .items)
    }

    public func item(_ id: String) -> Item? { items.first { $0.id == id } }
}

// MARK: - Conditions

/// The circumstances an item can be asked under. None of them should change
/// a well-behaved model's answer; a change is what the check reports.
public struct Conditions: Codable, Sendable {
    public var dates: [DateCondition]
    public var contexts: [ContextCondition]
    public var depths: [DepthCondition]

    public init(dates: [DateCondition] = [.init(id: "none")],
                contexts: [ContextCondition] = [.init(id: "plain", text: "")],
                depths: [DepthCondition] = [.init(id: "fresh", priorTurns: 0)]) {
        self.dates = dates
        self.contexts = contexts
        self.depths = depths
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dates = try c.decodeIfPresent([DateCondition].self, forKey: .dates) ?? [.init(id: "none")]
        contexts = try c.decodeIfPresent([ContextCondition].self, forKey: .contexts) ?? [.init(id: "plain", text: "")]
        depths = try c.decodeIfPresent([DepthCondition].self, forKey: .depths) ?? [.init(id: "fresh", priorTurns: 0)]
    }
}

public struct DateCondition: Codable, Sendable, Hashable {
    public var id: String
    /// Days from the real date. Nil with id "real" is today; nil with
    /// "none" states no date at all.
    public var offsetDays: Int?
    public init(id: String, offsetDays: Int? = nil) { self.id = id; self.offsetDays = offsetDays }
}

public struct ContextCondition: Codable, Sendable, Hashable {
    public var id: String
    /// One sentence the task does not depend on; `<place>` and the like are
    /// filled from the bank's context lists.
    public var text: String
    public init(id: String, text: String) { self.id = id; self.text = text }
}

public struct DepthCondition: Codable, Sendable, Hashable {
    public var id: String
    public var priorTurns: Int
    public var filler: String?
    public init(id: String, priorTurns: Int, filler: String? = nil) {
        self.id = id; self.priorTurns = priorTurns; self.filler = filler
    }
}

// MARK: - Items

public struct Item: Codable, Sendable {
    public var id: String
    public var module: Module
    public var `class`: String?
    public var axis: String?

    // facts, work: one prompt.
    public var prompt: String?
    // values (mirrored-pair): the same request from each side.
    public var variants: [Variant]?
    // values (choice-likelihood): one statement in several wordings.
    public var wordings: [Wording]?
    public var options: [String]?
    // candour: a question asked plainly and with the asker's view attached.
    public var question: String?
    public var framings: [Framing]?
    // work: an app task on supplied texts.
    public var task: String?
    public var inputs: [String]?
    public var mirrorOf: String?
    // dialogue: a candour item, then a ladder of follow-ups.
    public var opens: String?
    public var ladder: [Step]?

    public var scoring: Scoring
    public var reference: String?
    public var note: String?

    public enum Module: String, Codable, Sendable {
        case facts, values, candour, work, dialogue
    }

    public struct Variant: Codable, Sendable {
        public var side: String
        public var wording: Int
        public var prompt: String
    }

    /// A wording, given as plain text or as `{ "text": …, "reversed": true }`
    /// when agreeing with it means the opposite of agreeing with the first.
    public struct Wording: Codable, Sendable {
        public var text: String
        public var reversed: Bool

        public init(text: String, reversed: Bool = false) { self.text = text; self.reversed = reversed }

        public init(from decoder: Decoder) throws {
            if let text = try? decoder.singleValueContainer().decode(String.self) {
                self.init(text: text)
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(text: try c.decode(String.self, forKey: .text),
                      reversed: try c.decodeIfPresent(Bool.self, forKey: .reversed) ?? false)
        }
    }

    public struct Framing: Codable, Sendable {
        public var id: String
        public var prefix: String
    }

    public struct Step: Codable, Sendable {
        public enum Move: String, Codable, Sendable { case pressure, evidence }
        public var move: Move
        public var user: String
    }

    public struct Scoring: Codable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case exact, unanswerable, label
            case choiceLikelihood = "choice-likelihood"
            case mirroredPair = "mirrored-pair"
            case framingShift = "framing-shift"
            case trajectory
            /// Contested evidence: does the answer give each main position?
            case coverage
        }
        public var type: Kind
        public var accept: [String]?
        /// For a choice: what each option counts as, −1…1.
        public var direction: [String: Double]?
        /// For a label task: every label the answer may give.
        public var labels: [String]?
        /// For coverage: each position the answer should give, and phrases
        /// any one of which counts as giving it.
        public var positions: [Position]?
    }

    public struct Position: Codable, Sendable {
        public var name: String
        public var any: [String]
    }
}

// MARK: - Conversation

public struct Turn: Codable, Sendable, Hashable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public var role: Role
    public var text: String
    public init(_ role: Role, _ text: String) { self.role = role; self.text = text }
}
