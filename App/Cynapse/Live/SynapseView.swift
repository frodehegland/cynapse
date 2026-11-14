// SynapseView.swift — the check as a living network of synapses.
//
// Every question in the bank is a node: dim until it is asked, then lit in
// blue. Every answer the model gives is an orange node beside its question,
// joined to it by a thread of light. When the same question is asked again
// in another situation, its answers are joined to one another, so repeated
// questions grow into small webs; questions of the same kind are threaded
// together. The whole network turns slowly in depth. Blue and orange only
// tell the questions from the model's answers — they never mean good or bad.
// In Retro, the palette's line and text colours take their places.

import SwiftUI
import ModelCheck

struct SynapseView: View {
    let live: LiveState
    let bank: Bank?
    var palette: RetroPalette? = nil

    private var questionColor: Color { palette?.lineColor ?? Color(red: 0.36, green: 0.52, blue: 1.0) }
    private var answerColor: Color { palette?.textColor ?? Color(red: 1.0, green: 0.55, blue: 0.22) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { context, size in
                draw(&context, size: size, t: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 14) {
                legend(questionColor, "the questions")
                legend(answerColor, "the model's answers")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(questionColor.mix(with: .white, by: 0.35))
            .padding(.trailing, 24).padding(.bottom, 64)
            .opacity(0.75)
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7).shadow(color: color, radius: 4)
            Text(text)
        }
    }

    // MARK: The network

    private struct Point3 { var x, y, z: Double }

    private static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    /// A repeatable pseudo-random number in -1…1 from a string and a salt.
    private static func unit(_ s: String, _ salt: UInt64) -> Double {
        var x = hash(s) ^ (salt &* 0x9E3779B97F4A7C15)
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        x ^= x >> 31
        return Double(x % 20001) / 10000 - 1
    }

    /// Each kind of question has its own region of the cloud.
    private static let centres: [Item.Module: Point3] = [
        .facts: Point3(x: -0.55, y: -0.25, z: 0.2),
        .values: Point3(x: 0.15, y: 0.1, z: -0.1),
        .candour: Point3(x: 0.55, y: -0.35, z: 0.3),
        .dialogue: Point3(x: 0.45, y: 0.45, z: -0.3),
        .work: Point3(x: -0.35, y: 0.5, z: -0.2),
    ]

    /// One cloud for the whole check, each kind of question leaning toward
    /// its own side of it.
    private func position(of item: Item) -> Point3 {
        let c = Self.centres[item.module] ?? Point3(x: 0, y: 0, z: 0)
        return Point3(x: c.x * 0.35 + Self.unit(item.id, 1) * 0.62,
                      y: c.y * 0.35 + Self.unit(item.id, 2) * 0.45,
                      z: c.z * 0.35 + Self.unit(item.id, 3) * 0.55)
    }

    /// An answer reaches out from its question, so the threads are long and
    /// cross one another, as synapses do.
    private func answerPosition(_ exchange: Exchange, near p: Point3) -> Point3 {
        let r = 0.16 + 0.34 * abs(Self.unit(exchange.key, 4))
        var d = Point3(x: Self.unit(exchange.key, 5), y: Self.unit(exchange.key, 6) * 0.8, z: Self.unit(exchange.key, 7))
        let length = max(0.001, (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot())
        d = Point3(x: d.x / length, y: d.y / length, z: d.z / length)
        return Point3(x: p.x + d.x * r, y: p.y + d.y * r, z: p.z + d.z * r)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        guard let bank else { return }
        let angle = t * 0.035
        let tilt = 0.32 + 0.06 * sin(t * 0.05)
        let scale = min(size.width, size.height) * 0.78
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)

        /// Rotate, tilt and project: the point on screen, and how near it is (0 far … 1 near).
        func project(_ p: Point3) -> (CGPoint, Double) {
            let x1 = p.x * cos(angle) + p.z * sin(angle)
            let z1 = -p.x * sin(angle) + p.z * cos(angle)
            let y1 = p.y * cos(tilt) - z1 * sin(tilt)
            let z2 = p.y * sin(tilt) + z1 * cos(tilt)
            let perspective = 2.4 / (2.4 + z2)
            return (CGPoint(x: centre.x + x1 * scale * perspective, y: centre.y + y1 * scale * perspective), max(0, min(1, (1 - z2) / 2)))
        }

        let items = bank.items
        let itemPoints = Dictionary(uniqueKeysWithValues: items.map { ($0.id, position(of: $0)) })
        let asked = live.askedItems.union(live.current.map { [$0.itemId] } ?? [])
        let newest = live.exchanges.suffix(6).map(\.key)

        context.blendMode = .plusLighter

        // Threads between neighbouring questions: each to its nearest four.
        for item in items {
            guard let p = itemPoints[item.id] else { continue }
            let near = items.filter { $0.id != item.id }
                .sorted { distance(itemPoints[$0.id]!, p) < distance(itemPoints[$1.id]!, p) }
                .prefix(4)
            for other in near where other.id > item.id {
                let (a, da) = project(p), (b, db) = project(itemPoints[other.id]!)
                let lit = asked.contains(item.id) && asked.contains(other.id)
                stroke(&context, a, b, questionColor.opacity((lit ? 0.55 : 0.08) * (0.35 + 0.65 * (da + db) / 2)), width: lit ? 0.8 : 0.5)
            }
        }

        // Answers: joined to their question, and to the other answers to it.
        var lastAnswer: [String: (CGPoint, Double)] = [:]
        for exchange in live.exchanges.suffix(900) {
            guard let q = itemPoints[exchange.itemId] else { continue }
            let (qp, qd) = project(q)
            let (ap, ad) = project(answerPosition(exchange, near: q))
            let fresh = newest.contains(exchange.key)
            let depth = 0.3 + 0.7 * (qd + ad) / 2
            // Blue at the question, orange at the answer.
            gradientStroke(&context, qp, ap, from: questionColor.opacity((fresh ? 0.8 : 0.3) * depth),
                           to: answerColor.opacity((fresh ? 0.9 : 0.4) * depth), width: fresh ? 1.3 : 0.6)
            if let (previous, pd) = lastAnswer[exchange.itemId] {
                stroke(&context, previous, ap, answerColor.opacity(0.14 * (0.3 + 0.7 * (pd + ad) / 2)), width: 0.45)
            }
            lastAnswer[exchange.itemId] = (ap, ad)
            glow(&context, ap, depth: ad, color: answerColor, radius: fresh ? 2.6 : 1.3, bright: fresh ? 1 : 0.7)
        }

        // The question being asked now: its thread reaching out as the
        // answer is written.
        if let current = live.current, let q = itemPoints[current.itemId] {
            let (qp, qd) = project(q)
            let (ap, _) = project(answerPosition(current, near: q))
            let grown = min(1, Double(current.answer.count) / 160)
            let tip = CGPoint(x: qp.x + (ap.x - qp.x) * grown, y: qp.y + (ap.y - qp.y) * grown)
            stroke(&context, qp, tip, answerColor.opacity(0.9), width: 1.6)
            let pulse = 0.5 + 0.5 * sin(t * 5)
            glow(&context, qp, depth: qd, color: questionColor, radius: 4 + 3 * pulse, bright: 1)
        }

        // The questions themselves: dim until asked.
        for item in items {
            guard let p = itemPoints[item.id] else { continue }
            let (sp, depth) = project(p)
            let lit = asked.contains(item.id)
            glow(&context, sp, depth: depth, color: questionColor, radius: lit ? 3.2 : 1.6, bright: lit ? 1 : 0.3)
        }
    }

    private func distance(_ a: Point3, _ b: Point3) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
        return dx * dx + dy * dy + dz * dz
    }

    private func gradientStroke(_ context: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, from: Color, to: Color, width: CGFloat) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        context.stroke(path, with: .linearGradient(Gradient(colors: [from, to]), startPoint: a, endPoint: b), lineWidth: width)
    }

    private func stroke(_ context: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ color: Color, width: CGFloat) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        context.stroke(path, with: .color(color), lineWidth: width)
    }

    /// A point of light: a soft halo, larger and fainter further back, as
    /// out of focus; a bright core.
    private func glow(_ context: inout GraphicsContext, _ p: CGPoint, depth: Double, color: Color, radius: Double, bright: Double) {
        let blur = 1 + (1 - depth) * 2
        let halo = radius * 2.4 * blur
        context.fill(Path(ellipseIn: CGRect(x: p.x - halo, y: p.y - halo, width: halo * 2, height: halo * 2)),
                     with: .radialGradient(Gradient(colors: [color.opacity(0.3 * bright), color.opacity(0)]),
                                           center: p, startRadius: 0, endRadius: halo))
        let core = radius * (0.5 + 0.5 * depth)
        context.fill(Path(ellipseIn: CGRect(x: p.x - core, y: p.y - core, width: core * 2, height: core * 2)),
                     with: .color(Color.white.opacity(0.85 * bright * (0.4 + 0.6 * depth))))
    }
}
