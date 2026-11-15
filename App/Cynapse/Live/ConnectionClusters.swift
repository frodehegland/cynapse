// ConnectionClusters.swift — where Connections gathers its dots once a
// check is done, so its leanings can be seen.
//
// Contested questions: one bar per axis, running between the two
// positions the bank's authors published for it. Each statement the model
// answered consistently sits along its bar at where its answers fell; each
// answer, in each situation it was asked in, sits at its own score, so an
// answer that moved when the model was told something about the asker
// shows as a spread. Statements it answered both ways gather above the
// bar ("no stable position"); those it declined, or was asked to argue
// each side of, gather below. The lean the profile reports is a tick on
// the bar, in a neutral light: a position is never rated.
//
// Every other question gathers into a ball by how it rated.

import SwiftUI
import ModelCheck

struct Point3 { var x, y, z: Double }

/// Repeatable scatter, from a string and a salt.
enum Scatter {
    static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    /// A pseudo-random number in -1…1.
    static func unit(_ s: String, _ salt: UInt64) -> Double {
        var x = hash(s) ^ (salt &* 0x9E3779B97F4A7C15)
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        x ^= x >> 31
        return Double(x % 20001) / 10000 - 1
    }
}

struct ClusterLayout {
    struct Label {
        let text: String
        let at: Point3
        let anchor: UnitPoint
        var size: CGFloat = 10
        /// A title: clicking it shows its group alone.
        var strong = false
        /// The title this label belongs under: an axis, or "other".
        var group = ""
    }

    private(set) var items: [String: Point3] = [:]
    private(set) var labels: [Label] = []
    private(set) var bars: [(from: Point3, to: Point3, group: String)] = []
    /// The reported lean on each axis that has one.
    private(set) var ticks: [(at: Point3, group: String)] = []
    /// Each question's group: its axis, or "other" for every other question.
    private(set) var groupOf: [String: String] = [:]
    /// Each axis's row, by question.
    private var rows: [String: Double] = [:]
    /// Each answer's own score along its axis, by outcome key.
    private var scores: [String: Double] = [:]

    private static let axisOrder = ["economic", "social", "geopolitical", "religious"]
    private static let half = 0.75

    private static func isPlain(_ o: Scorer.Outcome) -> Bool {
        o.pass == 1 && o.condition.hasPrefix("date:none|context:plain|depth:fresh")
    }

    @MainActor init(bank: Bank, live: LiveState) {
        // Each question's result as asked plainly, else its first.
        var plain: [String: Scorer.Outcome] = [:]
        for entry in live.outcomes {
            let o = entry.outcome
            if Self.isPlain(o) { if !(plain[o.itemId].map(Self.isPlain) ?? false) { plain[o.itemId] = o } }
            else if plain[o.itemId] == nil { plain[o.itemId] = o }
            if let s = o.detail.wordingScores, !s.isEmpty {
                scores["\(o.itemId)|\(o.condition)|\(o.pass)"] = s.reduce(0, +) / Double(s.count)
            }
        }

        // The contested questions, an axis to a row.
        let axes = Self.axisOrder.filter { bank.axes[$0] != nil } + bank.axes.keys.filter { !Self.axisOrder.contains($0) }.sorted()
        var unplaced: [Item] = []
        for (index, axis) in axes.enumerated() {
            let row = -0.52 + Double(index) * 0.18
            let name = axis.prefix(1).uppercased() + axis.dropFirst()
            let lean = live.profile?.lean.first { $0.axis == axis }
            labels.append(Label(text: lean?.text ?? name, at: Point3(x: -Self.half, y: row - 0.07, z: 0), anchor: .bottomLeading, size: 11, strong: true, group: axis))
            if let poles = bank.axes[axis] {
                labels.append(Label(text: "← " + poles.negative, at: Point3(x: -Self.half, y: row + 0.014, z: 0), anchor: .topLeading, group: axis))
                labels.append(Label(text: poles.positive + " →", at: Point3(x: Self.half, y: row + 0.014, z: 0), anchor: .topTrailing, group: axis))
            }
            bars.append((Point3(x: -Self.half, y: row, z: 0), Point3(x: Self.half, y: row, z: 0), axis))
            if let value = lean?.value { ticks.append((Point3(x: value * Self.half, y: row, z: 0), axis)) }

            var unstable = 0, apart = 0
            for item in bank.items where item.module == .values && item.axis == axis {
                guard let outcome = plain[item.id] else { unplaced.append(item); continue }
                groupOf[item.id] = axis
                rows[item.id] = row
                let u = { (salt: UInt64) in Scatter.unit(item.id, salt) }
                let s = outcome.detail.wordingScores ?? []
                let signs = Set(s.map { $0 > 0.05 ? 1 : $0 < -0.05 ? -1 : 0 })
                if s.isEmpty {
                    apart += 1
                    items[item.id] = Point3(x: -0.2 + u(21) * 0.06, y: row + 0.055 + u(22) * 0.01, z: u(23) * 0.04)
                } else if signs.contains(1) && signs.contains(-1) {
                    unstable += 1
                    items[item.id] = Point3(x: u(21) * 0.06, y: row - 0.04 + u(22) * 0.01, z: u(23) * 0.04)
                } else {
                    let mean = s.reduce(0, +) / Double(s.count)
                    items[item.id] = Point3(x: max(-1, min(1, mean)) * Self.half, y: row + u(22) * 0.012, z: u(23) * 0.04)
                }
            }
            if unstable > 0 { labels.append(Label(text: "no stable position", at: Point3(x: 0.09, y: row - 0.04, z: 0), anchor: .leading, size: 9, group: axis)) }
            if apart > 0 { labels.append(Label(text: "declined, or asked to argue each side", at: Point3(x: -0.15, y: row + 0.055, z: 0), anchor: .leading, size: 9, group: axis)) }
        }

        // Every other question, by how it rated.
        var groups: [(word: String, items: [Item])] = [
            ("good", []), ("acceptable", []), ("questionable", []), ("wrong", []), ("not rated", []), ("not asked", []),
        ]
        func add(_ item: Item, to word: String) { if let i = groups.firstIndex(where: { $0.word == word }) { groups[i].items.append(item) } }
        for item in bank.items where !(item.module == .values && item.axis.map { bank.axes[$0] != nil } == true) {
            guard let outcome = plain[item.id] else { unplaced.append(item); continue }
            switch outcome.assessment(item: item) {
            case .good: add(item, to: "good")
            case .ok: add(item, to: "acceptable")
            case .questionable: add(item, to: "questionable")
            case .wrong: add(item, to: "wrong")
            case .neutral: add(item, to: "not rated")
            }
        }
        for item in unplaced { add(item, to: "not asked") }
        let shown = groups.filter { !$0.items.isEmpty }
        let y = 0.36
        labels.append(Label(text: "Every other question, by how it rated", at: Point3(x: -Self.half, y: y - 0.13, z: 0), anchor: .bottomLeading, size: 11, strong: true, group: "other"))
        for (index, group) in shown.enumerated() {
            let x = shown.count == 1 ? 0 : -Self.half + Double(index) * (2 * Self.half) / Double(shown.count - 1)
            let r = min(0.1, 0.025 + 0.016 * Double(group.items.count).squareRoot())
            for item in group.items {
                let u = { (salt: UInt64) in Scatter.unit(item.id, salt) }
                items[item.id] = Point3(x: x + u(11) * r, y: y + u(12) * r, z: u(13) * r)
                groupOf[item.id] = "other"
            }
            labels.append(Label(text: "\(group.word) · \(group.items.count)", at: Point3(x: x, y: y + r + 0.025, z: 0), anchor: .top, group: "other"))
        }
    }

    /// An answer: at its own score on its axis when it has one, else close
    /// beside its question.
    func answer(_ exchange: Exchange, question q: Point3) -> Point3 {
        let u = { (salt: UInt64) in Scatter.unit(exchange.key, salt) }
        if let row = rows[exchange.itemId], let score = scores[exchange.outcomeKey] {
            // Spread a little, so answers on the same side don't stack into one streak.
            return Point3(x: max(-1, min(1, score)) * Self.half + u(37) * 0.035, y: row + u(31) * 0.022, z: u(32) * 0.05)
        }
        let r = 0.02 + 0.035 * abs(u(33))
        var d = Point3(x: u(34), y: u(35), z: u(36))
        let length = max(0.001, (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot())
        d = Point3(x: d.x / length, y: d.y / length, z: d.z / length)
        return Point3(x: q.x + d.x * r, y: q.y + d.y * r, z: q.z + d.z * r)
    }
}
