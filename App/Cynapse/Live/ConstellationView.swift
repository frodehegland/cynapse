// ConstellationView.swift — the four axes as a quiet field of stars.
//
// Each statement the model answers becomes a star near its axis: a steady
// star for a consistent answer, a broken one for an inconsistent answer, a
// hollow one for a refusal to choose. Stars are never placed along the
// axis by their answer: a lean from a handful of answers is exactly the
// false precision the method avoids. Only when an axis has enough
// consistent answers does its marker appear, once, with its interval —
// and when the check is done, the profile's own lean replaces it. Other
// questions gather as stars around the edge; answers fly in from the
// centre, as words fly in Author's Starfield.

import SwiftUI
import ModelCheck

struct ConstellationView: View {
    let live: LiveState
    let bank: Bank?
    let ink: Color

    private let axes = ["economic", "social", "geopolitical", "religious"]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.36
                drawFlight(&context, size: size, centre: centre, t: t)
                for (index, axis) in axes.enumerated() {
                    drawAxis(&context, axis: axis, angle: Double(index) * .pi / 4, centre: centre, radius: radius, t: t)
                }
                drawOthers(&context, centre: centre, radius: radius * 1.28, t: t)
            }
        }
    }

    private func drawAxis(_ context: inout GraphicsContext, axis: String, angle: Double, centre: CGPoint, radius: CGFloat, t: Double) {
        let dx = CGFloat(cos(angle)), dy = CGFloat(sin(angle))
        let a = CGPoint(x: centre.x - dx * radius, y: centre.y - dy * radius)
        let b = CGPoint(x: centre.x + dx * radius, y: centre.y + dy * radius)
        var line = Path(); line.move(to: a); line.addLine(to: b)
        context.stroke(line, with: .color(ink.opacity(0.25)), lineWidth: 0.6)

        let poles = bank?.axes[axis]
        context.draw(Text(poles?.negative ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(ink.opacity(0.55)),
                     at: CGPoint(x: a.x - dx * 14, y: a.y - dy * 14))
        context.draw(Text(poles?.positive ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(ink.opacity(0.55)),
                     at: CGPoint(x: b.x + dx * 14, y: b.y + dy * 14))

        // This axis's stars, in a band beside the line, in arrival order.
        let stars = live.outcomes.filter { $0.axis == axis && $0.module == .values && $0.outcome.pass == 1 }
        let normal = CGPoint(x: -dy, y: dx)
        for (i, star) in stars.enumerated() {
            let along = CGFloat((Double(i) + 0.5) / 12 - 0.5) * radius * 1.6
            let wobble = CGFloat(sin(t * 0.6 + Double(i))) * 2
            let p = CGPoint(x: centre.x + dx * along + normal.x * (18 + wobble), y: centre.y + dy * along + normal.y * (18 + wobble))
            let scores = star.outcome.detail.wordingScores ?? []
            let signs = Set(scores.map { $0 > 0.05 ? 1 : $0 < -0.05 ? -1 : 0 })
            let rect = CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
            if scores.isEmpty {
                context.stroke(Path(ellipseIn: rect), with: .color(ink.opacity(0.7)), lineWidth: 1)
            } else if signs.contains(1) && signs.contains(-1) {
                var cross = Path()
                cross.move(to: CGPoint(x: rect.minX, y: rect.midY)); cross.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                context.stroke(cross, with: .color(ink.opacity(0.7)), lineWidth: 1)
            } else {
                context.fill(Path(ellipseIn: rect), with: .color(ink.opacity(0.9)))
            }
        }

        // The marker: the profile's when done; otherwise only with enough
        // consistent answers, and only as counts until the end.
        let threshold = bank?.bank.kind == "pilot" ? 6 : 8
        let counts = live.axisCounts[axis] ?? (0, 0, 0)
        if let lean = live.profile?.lean.first(where: { $0.axis == axis }), let value = lean.value, let interval = lean.interval {
            func point(_ v: Double) -> CGPoint { CGPoint(x: centre.x + dx * CGFloat(v) * radius, y: centre.y + dy * CGFloat(v) * radius) }
            var span = Path(); span.move(to: point(interval[0])); span.addLine(to: point(interval[1]))
            context.stroke(span, with: .color(ink.opacity(0.6)), lineWidth: 4)
            let m = point(value)
            context.fill(Path(ellipseIn: CGRect(x: m.x - 6, y: m.y - 6, width: 12, height: 12)), with: .color(ink))
        } else if let lean = live.profile?.lean.first(where: { $0.axis == axis }) {
            context.draw(Text(lean.value == nil ? lean.text : "").font(.system(size: 12, design: .serif)).foregroundStyle(ink.opacity(0.8)),
                         at: CGPoint(x: centre.x + normal.x * 44 + dx * radius * 0.5, y: centre.y + normal.y * 44 + dy * radius * 0.5))
        } else if counts.stable >= threshold {
            context.draw(Text("enough consistent answers; shown when the check is done").font(.system(size: 10, design: .monospaced)).foregroundStyle(ink.opacity(0.5)),
                         at: CGPoint(x: centre.x + normal.x * 40 + dx * radius * 0.5, y: centre.y + normal.y * 40 + dy * radius * 0.5))
        }
    }

    /// Facts, candour, conversations and work: stars on an outer ring.
    private func drawOthers(_ context: inout GraphicsContext, centre: CGPoint, radius: CGFloat, t: Double) {
        let others = live.outcomes.filter { $0.module != .values }
        for (i, star) in others.enumerated() {
            let angle = Double(i) * 2.399963 + t * 0.01   // golden angle, slowly turning
            let r = radius + CGFloat(i % 5) * 9
            let p = CGPoint(x: centre.x + CGFloat(cos(angle)) * r, y: centre.y + CGFloat(sin(angle)) * r)
            let twinkle = 0.55 + 0.45 * sin(t * 1.3 + Double(i))
            context.fill(Path(ellipseIn: CGRect(x: p.x - 1.6, y: p.y - 1.6, width: 3.2, height: 3.2)), with: .color(ink.opacity(0.4 + 0.5 * twinkle)))
        }
    }

    /// The words of the answer being written fly outward from the centre.
    private func drawFlight(_ context: inout GraphicsContext, size: CGSize, centre: CGPoint, t: Double) {
        let words = (live.current?.answer ?? live.exchanges.last?.answer ?? "").split(separator: " ").suffix(24)
        for (i, word) in words.enumerated() {
            let seed = Double(word.hashValue % 1000) / 1000
            let angle = seed * 2 * .pi
            let phase = (t * 0.08 + Double(i) * 0.04 + seed).truncatingRemainder(dividingBy: 1)
            let distance = CGFloat(phase) * max(size.width, size.height) * 0.6
            let p = CGPoint(x: centre.x + CGFloat(cos(angle)) * distance, y: centre.y + CGFloat(sin(angle)) * distance)
            context.draw(Text(String(word)).font(.system(size: 10 + 10 * CGFloat(phase), design: .serif)).foregroundStyle(ink.opacity(0.25 * (1 - phase))),
                         at: p)
        }
    }
}
