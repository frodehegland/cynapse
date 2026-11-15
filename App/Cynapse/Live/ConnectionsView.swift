// ConnectionsView.swift — the check as a living network of connections.
//
// Every question in the bank is a node: dim until it is asked, then lit in
// blue. Every answer the model gives is a node beside its question, joined
// to it by a thread of light, coloured by how that result rates: green
// good, yellow acceptable, orange questionable, red wrong or a serious
// warning. A position on a contested question is never rated and glows a
// soft neutral white. When the same question is asked again in another
// situation, its answers are joined to one another, so repeated questions
// grow into small webs; neighbouring questions are threaded together. The
// whole network turns slowly in depth; dragging turns it by hand, and it
// takes up its own slow turn again a few seconds after it is let go.
// Once the check is done the dots gather into clusters that show its
// leanings (ConnectionClusters.swift); a pill switches back.
// Clicking a dot opens its question, and the answer, in the panel beside.
// In Retro, the questions take the palette's colour; the ratings keep
// theirs, since they carry meaning.

import SwiftUI
import ModelCheck

/// A dot clicked in the network: a question, or one answer to it.
struct ConnectionPick: Identifiable, Equatable {
    let itemId: String
    /// The answer's exchange, or nil for the question itself.
    let exchangeKey: String?
    var id: String { exchangeKey ?? "question:" + itemId }
}

struct ConnectionsView: View {
    let live: LiveState
    let bank: Bank?
    var palette: RetroPalette? = nil
    /// The dot shown in the panel, ringed.
    var picked: ConnectionPick? = nil
    /// A dot was clicked.
    var pick: (ConnectionPick) -> Void = { _ in }
    /// Fixes the layout, for snapshots.
    var fixedClusters: Bool? = nil

    /// The turn at `spinFrom`; after it the network turns slowly by itself.
    @State private var yaw = 0.0
    @State private var spinFrom = Date.timeIntervalSinceReferenceDate
    @State private var pitch = 0.32
    /// The turn and tilt when a drag began.
    @State private var dragBase: (yaw: Double, pitch: Double)?
    /// Gathered into clusters, once the check is done.
    @State private var clustered = false
    /// When the dots last set off between network and clusters.
    @State private var layoutChanged = -1e9
    /// The turn still to unwind, as the clusters come round to face the front.
    @State private var unwind: (from: Double, start: Double)?
    /// The title clicked in the clusters: only its group is shown.
    @State private var focus: String?

    private var checkDone: Bool { live.profile != nil && !live.running }

    private var questionColor: Color { palette?.lineColor ?? Color(red: 0.36, green: 0.52, blue: 1.0) }
    /// An answer not yet rated (its other parts still being asked).
    private var pendingColor: Color { Color(white: 0.75) }

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                Canvas { context, size in
                    draw(&context, size: size, t: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
            .contentShape(Rectangle())
            .gesture(rotation)
            .onTapGesture(coordinateSpace: .local) { location in
                // A title shows its group alone, and again shows them all.
                if let group = titleHit(at: location, size: geometry.size) {
                    withAnimation { focus = focus == group ? nil : group }
                } else if let hit = hit(at: location, size: geometry.size) {
                    pick(hit)
                }
            }
        }
        .onAppear { if checkDone { setClustered(true) } }
        .onChange(of: checkDone) { _, done in setClustered(done) }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 14) {
                if checkDone {
                    Button(clustered ? "Network" : "Clusters") { setClustered(!clustered) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .help(clustered ? "Spread the dots out as a network again" : "Gather the dots to show where the answers lean")
                }
                legend(questionColor, "questions")
                legend(Assessment.good.color, "good")
                legend(Assessment.ok.color, "acceptable")
                legend(Assessment.questionable.color, "questionable")
                legend(Assessment.wrong.color, "wrong")
                legend(Assessment.neutral.color, "a position, not rated")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(questionColor.mix(with: .black, by: 0.3))
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

    // MARK: Turning by hand

    private func angle(at t: Double) -> Double {
        let elapsed = max(0, t - spinFrom)
        if let fixedClusters { return fixedClusters ? 0 : yaw + elapsed * 0.035 }
        guard clustered else { return yaw + elapsed * 0.035 }
        // Clustered: a gentle sway about the front, where the words read.
        var a = yaw + 0.22 * sin(elapsed * 0.15)
        if let unwind { a += unwind.from * (1 - Self.ease((t - unwind.start) / 3)) }
        return a
    }

    private static func ease(_ x: Double) -> Double {
        let s = min(1, max(0, x))
        return s * s * (3 - 2 * s)
    }

    /// 0 the network, 1 the clusters, easing between.
    private func blend(at t: Double) -> Double {
        if let fixedClusters { return fixedClusters ? 1 : 0 }
        let e = Self.ease((t - layoutChanged) / 3)
        return clustered ? e : 1 - e
    }

    private func setClustered(_ on: Bool) {
        guard on != clustered else { return }
        let now = Date.timeIntervalSinceReferenceDate
        let a = angle(at: now), b = blend(at: now)
        if on {
            unwind = (remainder(a, 2 * .pi), now)
            yaw = 0
        } else {
            unwind = nil
            yaw = a
        }
        spinFrom = now
        clustered = on
        if !on { focus = nil }
        // Carry on from wherever a half-made move had got to.
        layoutChanged = now - 3 * (on ? b : 1 - b)
    }
    private func tilt(at t: Double) -> Double { pitch + 0.06 * sin(t * 0.05) }

    private var rotation: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let now = Date.timeIntervalSinceReferenceDate
                if dragBase == nil { dragBase = (angle(at: now), pitch); unwind = nil }
                guard let base = dragBase else { return }
                yaw = base.yaw + value.translation.width * 0.008
                pitch = min(1.4, max(-1.4, base.pitch + value.translation.height * 0.006))
                spinFrom = .infinity // held still while dragged
            }
            .onEnded { _ in
                dragBase = nil
                // Its own slow turn again, a few seconds after it is let go.
                spinFrom = Date.timeIntervalSinceReferenceDate + 4
            }
    }

    // MARK: The network

    /// Turns, tilts and projects the cloud onto the screen.
    private struct Camera {
        let angle, tilt, scale: Double
        let centre: CGPoint

        /// The point on screen, and how near it is (0 far … 1 near).
        func project(_ p: Point3) -> (CGPoint, Double) {
            let x1 = p.x * cos(angle) + p.z * sin(angle)
            let z1 = -p.x * sin(angle) + p.z * cos(angle)
            let y1 = p.y * cos(tilt) - z1 * sin(tilt)
            let z2 = p.y * sin(tilt) + z1 * cos(tilt)
            let perspective = 2.4 / (2.4 + z2)
            return (CGPoint(x: centre.x + x1 * scale * perspective, y: centre.y + y1 * scale * perspective), max(0, min(1, (1 - z2) / 2)))
        }
    }

    private func camera(size: CGSize, t: Double) -> Camera {
        // A little smaller when clustered, to leave room for the words.
        Camera(angle: angle(at: t), tilt: tilt(at: t), scale: min(size.width, size.height) * (0.78 - 0.12 * blend(at: t)),
               centre: CGPoint(x: size.width / 2, y: size.height / 2))
    }

    /// The dot under a click, the nearest within a few points; nearer dots
    /// win over ones behind them.
    private func hit(at location: CGPoint, size: CGSize) -> ConnectionPick? {
        guard let bank else { return nil }
        let camera = self.camera(size: size, t: Date.timeIntervalSinceReferenceDate)
        var best: (pick: ConnectionPick, score: Double)?
        func consider(_ pick: ConnectionPick, _ point: CGPoint, _ depth: Double) {
            let d = hypot(point.x - location.x, point.y - location.y)
            guard d < 12 * dotScale else { return }
            let score = d - depth * 3
            if best == nil || score < best!.score { best = (pick, score) }
        }
        let placed = placement(bank: bank, t: Date.timeIntervalSinceReferenceDate)
        let shown = shownTest(placed)
        for (id, p) in placed.items where shown(id) {
            let (sp, depth) = camera.project(p)
            consider(ConnectionPick(itemId: id, exchangeKey: nil), sp, depth)
        }
        for exchange in live.exchanges.suffix(900) where shown(exchange.itemId) {
            guard let a = placed.answer(exchange) else { continue }
            let (sp, depth) = camera.project(a)
            consider(ConnectionPick(itemId: exchange.itemId, exchangeKey: exchange.key), sp, depth)
        }
        return best?.pick
    }

    /// How sparse the check is: 1 for the full set of questions (60 or
    /// more), rising to 2.6 for a small one such as the Analysis Check's
    /// nine. A sparse cloud is drawn with larger dots, closer together.
    private var sparseness: Double {
        let count = Double(max(1, bank?.items.count ?? 60))
        return min(2.6, max(1, (60 / count).squareRoot()))
    }
    /// How far the cloud spreads: narrower as it thins.
    private var spread: Double { 1 / pow(sparseness, 0.6) }
    /// How large each dot is drawn: larger as the cloud thins.
    private var dotScale: Double { pow(sparseness, 0.8) }

    /// Whether a question's dots are shown: all of them, unless a title
    /// was clicked, when only its group's.
    private func shownTest(_ placed: Placement) -> (String) -> Bool {
        guard let focus, let groups = placed.clusters?.groupOf else { return { _ in true } }
        return { groups[$0] == focus }
    }

    /// The group of the title under a click, in the clusters. Titles are
    /// monospaced, so each one's box is worked out from its length.
    private func titleHit(at location: CGPoint, size: CGSize) -> String? {
        guard let bank, clustered else { return nil }
        let now = Date.timeIntervalSinceReferenceDate
        let placed = placement(bank: bank, t: now)
        guard let clusters = placed.clusters, placed.blend > 0.5 else { return nil }
        let camera = self.camera(size: size, t: now)
        for label in clusters.labels where label.strong && (focus == nil || focus == label.group) {
            let (p, _) = camera.project(label.at)
            let characters = label.text.count + (focus == label.group ? 11 : 0)
            let w = Double(characters) * Double(label.size) * 0.62, h = Double(label.size) * 1.5
            let box = CGRect(x: p.x - label.anchor.x * w, y: p.y - label.anchor.y * h, width: w, height: h).insetBy(dx: -6, dy: -6)
            if box.contains(location) { return label.group }
        }
        return nil
    }

    /// Each kind of question has its own region of the cloud.
    private static let centres: [Item.Module: Point3] = [
        .facts: Point3(x: -0.55, y: -0.25, z: 0.2),
        .values: Point3(x: 0.15, y: 0.1, z: -0.1),
        .candour: Point3(x: 0.55, y: -0.35, z: 0.3),
        .dialogue: Point3(x: 0.45, y: 0.45, z: -0.3),
        .work: Point3(x: -0.35, y: 0.5, z: -0.2),
        .analysis: Point3(x: 0, y: 0, z: 0),
    ]

    /// One cloud for the whole check, each kind of question leaning toward
    /// its own side of it.
    private func position(of item: Item) -> Point3 {
        let c = Self.centres[item.module] ?? Point3(x: 0, y: 0, z: 0)
        let s = spread
        return Point3(x: (c.x * 0.35 + Scatter.unit(item.id, 1) * 0.62) * s,
                      y: (c.y * 0.35 + Scatter.unit(item.id, 2) * 0.45) * s,
                      z: (c.z * 0.35 + Scatter.unit(item.id, 3) * 0.55) * s)
    }

    /// An answer reaches out from its question, so the threads are long and
    /// cross one another, as synapses do.
    private func answerPosition(_ exchange: Exchange, near p: Point3) -> Point3 {
        let r = (0.16 + 0.34 * abs(Scatter.unit(exchange.key, 4))) * spread
        var d = Point3(x: Scatter.unit(exchange.key, 5), y: Scatter.unit(exchange.key, 6) * 0.8, z: Scatter.unit(exchange.key, 7))
        let length = max(0.001, (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot())
        d = Point3(x: d.x / length, y: d.y / length, z: d.z / length)
        return Point3(x: p.x + d.x * r, y: p.y + d.y * r, z: p.z + d.z * r)
    }

    /// Where every dot is at a moment: in the network, in the clusters, or
    /// on its way between them.
    private struct Placement {
        var items: [String: Point3]
        var answer: (Exchange) -> Point3?
        var clusters: ClusterLayout?
        var blend: Double
    }

    private func placement(bank: Bank, t: Double) -> Placement {
        let network = Dictionary(uniqueKeysWithValues: bank.items.map { ($0.id, position(of: $0)) })
        let b = blend(at: t)
        guard b > 0 else {
            return Placement(items: network, answer: { e in network[e.itemId].map { answerPosition(e, near: $0) } }, clusters: nil, blend: 0)
        }
        let clusters = ClusterLayout(bank: bank, live: live)
        func mix(_ a: Point3, _ c: Point3) -> Point3 {
            Point3(x: a.x + (c.x - a.x) * b, y: a.y + (c.y - a.y) * b, z: a.z + (c.z - a.z) * b)
        }
        var items: [String: Point3] = [:]
        for (id, p) in network { items[id] = mix(p, clusters.items[id] ?? p) }
        return Placement(items: items, answer: { e in
            guard let q = network[e.itemId] else { return nil }
            return mix(answerPosition(e, near: q), clusters.answer(e, question: clusters.items[e.itemId] ?? q))
        }, clusters: clusters, blend: b)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        guard let bank else { return }
        let camera = self.camera(size: size, t: t)
        let project = camera.project

        let items = bank.items
        let placed = placement(bank: bank, t: t)
        let itemPoints = placed.items
        let loose = 1 - placed.blend // the network's own threads fade as clusters form
        let asked = live.askedItems.union(live.current.map { [$0.itemId] } ?? [])
        let newest = live.exchanges.suffix(6).map(\.key)
        let ratings = live.assessments(bank: bank)
        let shown = shownTest(placed)

        context.blendMode = .plusLighter

        // Threads between neighbouring questions: each to its nearest four.
        for item in items where shown(item.id) {
            guard let p = itemPoints[item.id] else { continue }
            let near = items.filter { $0.id != item.id }
                .sorted { distance(itemPoints[$0.id]!, p) < distance(itemPoints[$1.id]!, p) }
                .prefix(4)
            for other in near where other.id > item.id && shown(other.id) {
                let (a, da) = project(p), (b, db) = project(itemPoints[other.id]!)
                let lit = asked.contains(item.id) && asked.contains(other.id)
                stroke(&context, a, b, questionColor.opacity(loose * (lit ? 0.7 : 0.12) * (0.35 + 0.65 * (da + db) / 2)), width: lit ? 0.8 : 0.5)
            }
        }

        // Answers: joined to their question, and to the other answers to it.
        var lastAnswer: [String: (CGPoint, Double)] = [:]
        for exchange in live.exchanges.suffix(900) where shown(exchange.itemId) {
            guard let q = itemPoints[exchange.itemId], let a = placed.answer(exchange) else { continue }
            let (qp, qd) = project(q)
            let (ap, ad) = project(a)
            let fresh = newest.contains(exchange.key)
            let answerColor = ratings[exchange.outcomeKey]?.color ?? pendingColor
            let depth = 0.3 + 0.7 * (qd + ad) / 2
            // Blue at the question, orange at the answer.
            gradientStroke(&context, qp, ap, from: questionColor.opacity((fresh ? 0.9 : 0.42) * depth),
                           to: answerColor.opacity((fresh ? 1 : 0.55) * depth), width: (fresh ? 1.3 : 0.6) * dotScale.squareRoot())
            if let (previous, pd) = lastAnswer[exchange.itemId] {
                stroke(&context, previous, ap, answerColor.opacity(0.2 * (0.3 + 0.7 * (pd + ad) / 2)), width: 0.45)
            }
            lastAnswer[exchange.itemId] = (ap, ad)
            glow(&context, ap, depth: ad, color: answerColor, radius: (fresh ? 2.6 : 1.3) * dotScale, bright: fresh ? 1.15 : 0.85)
        }

        // The question being asked now: its thread reaching out as the
        // answer is written.
        if let current = live.current, shown(current.itemId), let q = itemPoints[current.itemId] {
            let (qp, qd) = project(q)
            let (ap, _) = project(answerPosition(current, near: q))
            let grown = min(1, Double(current.answer.count) / 160)
            let tip = CGPoint(x: qp.x + (ap.x - qp.x) * grown, y: qp.y + (ap.y - qp.y) * grown)
            stroke(&context, qp, tip, pendingColor.opacity(0.9), width: 1.6)
            let pulse = 0.5 + 0.5 * sin(t * 5)
            glow(&context, qp, depth: qd, color: questionColor, radius: (4 + 3 * pulse) * dotScale, bright: 1.15)
        }

        // The questions themselves: dim until asked.
        for item in items where shown(item.id) {
            guard let p = itemPoints[item.id] else { continue }
            let (sp, depth) = project(p)
            let lit = asked.contains(item.id)
            glow(&context, sp, depth: depth, color: questionColor, radius: (lit ? 3.2 : 1.6) * dotScale, bright: lit ? 1.15 : 0.45)
        }

        // The dot shown in the panel, ringed; an answer's question too.
        if let picked, shown(picked.itemId), let q = itemPoints[picked.itemId] {
            let (qp, _) = project(q)
            ring(&context, qp, color: questionColor, pulse: picked.exchangeKey == nil ? t : nil)
            if let key = picked.exchangeKey, let exchange = live.exchanges.last(where: { $0.key == key }), let a = placed.answer(exchange) {
                let (ap, _) = project(a)
                ring(&context, ap, color: ratings[exchange.outcomeKey]?.color ?? pendingColor, pulse: t)
            }
        }

        if let clusters = placed.clusters { drawFrame(clusters, &context, project: project, opacity: placed.blend) }
    }

    /// The clusters' bars, the reported leans, and their words.
    private func drawFrame(_ clusters: ClusterLayout, _ context: inout GraphicsContext,
                           project: (Point3) -> (CGPoint, Double), opacity: Double) {
        func inFocus(_ group: String) -> Bool { focus == nil || focus == group }
        for bar in clusters.bars where inFocus(bar.group) {
            let (a, _) = project(bar.from), (b, _) = project(bar.to)
            stroke(&context, a, b, questionColor.opacity(0.6 * opacity), width: 1)
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            stroke(&context, CGPoint(x: mid.x, y: mid.y - 4), CGPoint(x: mid.x, y: mid.y + 4), questionColor.opacity(0.6 * opacity), width: 1)
        }
        // The lean the profile reports: a position, so a neutral light.
        for tick in clusters.ticks where inFocus(tick.group) {
            let (p, _) = project(tick.at)
            stroke(&context, CGPoint(x: p.x, y: p.y - 11), CGPoint(x: p.x, y: p.y + 11), Assessment.neutral.color.opacity(0.95 * opacity), width: 2)
        }
        context.blendMode = .normal
        let ink = questionColor.mix(with: .black, by: 0.15)
        // Titles stand out in near white (the palette's own text colour in
        // Retro); the words beneath them stay quiet.
        let titleInk = palette?.textColor ?? Color(white: 0.96)
        for label in clusters.labels where inFocus(label.group) {
            let (p, _) = project(label.at)
            let font = Font.system(size: label.size, weight: label.strong ? .semibold : .regular, design: .monospaced)
            var text = Text(label.text).font(font).foregroundStyle((label.strong ? titleInk : ink.opacity(0.6)).opacity(opacity))
            if label.strong, focus == label.group {
                text = text + Text("   show all").font(.system(size: label.size - 1, design: .monospaced)).foregroundStyle(ink.opacity(0.75 * opacity))
            }
            context.draw(text, at: p, anchor: label.anchor)
        }
    }

    /// A ring round a picked dot, breathing when it is the one clicked.
    private func ring(_ context: inout GraphicsContext, _ p: CGPoint, color: Color, pulse t: Double?) {
        let r = 9 * dotScale + (t.map { 2 * sin($0 * 3) } ?? 0)
        context.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                       with: .color(color.opacity(0.95)), lineWidth: 1.4)
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
                     with: .radialGradient(Gradient(colors: [color.opacity(0.4 * bright), color.opacity(0)]),
                                           center: p, startRadius: 0, endRadius: halo))
        let core = radius * (0.5 + 0.5 * depth)
        context.fill(Path(ellipseIn: CGRect(x: p.x - core, y: p.y - core, width: core * 2, height: core * 2)),
                     with: .color(Color.white.opacity(min(1, 0.85 * bright) * (0.4 + 0.6 * depth))))
    }
}
