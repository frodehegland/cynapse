// RainView.swift — the Living Manuscript's Rain style: a port of Author's
// Matrix screensaver (WriteMatrixDream.swift, Frode Hegland, 10 Nov 2026).
//
// Each request falls in its own column as it is sent, its answer in the
// column beside it, so the two sides of a paired question fall side by
// side and a refused side shows as a short column beside a long one. Only
// what was really asked and answered rains: between new exchanges, earlier
// ones from this run fall again. One layer per falling text, moved by Core
// Animation, so the rain costs the main thread nothing between drops.

import SwiftUI
import AppKit
import QuartzCore

struct RainView: NSViewRepresentable {
    let live: LiveState
    let privacy: Bool

    func makeNSView(context: Context) -> RainNSView {
        let view = RainNSView()
        view.privacy = privacy
        return view
    }

    func updateNSView(_ view: RainNSView, context: Context) {
        view.privacy = privacy
        // A newly answered exchange: its prompt and answer side by side.
        if let last = live.exchanges.last, last.id != view.lastExchange {
            view.lastExchange = last.id
            view.dropPair(prompt: privacy && last.isSensitive ? "a contested statement" : last.prompt, answer: last.answer)
        }
        view.pool = live.exchanges.suffix(80).flatMap { [privacy && $0.isSensitive ? "a contested statement" : $0.prompt, $0.answer] }
    }
}

final class RainNSView: NSView {
    var pool: [String] = []
    var privacy = false
    var lastExchange: UUID?
    private var running = false
    private var nextPairColumn = 0
    private var busy: Set<Int> = []

    private static let fontSize: CGFloat = 16
    private static let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
    private static let lineHeight: CGFloat = ceil(fontSize * 1.18)
    private static let columnWidth: CGFloat = ceil(("M" as NSString).size(withAttributes: [.font: font]).width * 1.7)
    /// The longest text that falls whole; longer ones fall as their opening.
    private static let longest = 90
    private let rainColor = NSColor(calibratedRed: 0.2, green: 1, blue: 0.35, alpha: 1)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !running else { return }
        running = true
        for column in 0..<columns {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.5...6)) { [weak self] in self?.drop(in: column) }
        }
    }

    override func removeFromSuperview() {
        running = false
        super.removeFromSuperview()
    }

    private var columns: Int { max(2, Int(bounds.width / Self.columnWidth)) }

    /// The new exchange: prompt and answer in neighbouring columns.
    func dropPair(prompt: String, answer: String) {
        guard running else { return }
        let column = nextPairColumn % max(columns - 1, 1)
        nextPairColumn += max(2, columns / 7)
        fall(prompt, in: column, bright: true)
        fall(answer, in: column + 1, bright: true)
    }

    /// Ambient rain from earlier exchanges in this run.
    private func drop(in column: Int) {
        guard running else { return }
        if !busy.contains(column), let text = pool.randomElement() {
            fall(text, in: column, bright: false)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 1...3)) { [weak self] in self?.drop(in: column) }
        }
    }

    private func fall(_ raw: String, in column: Int, bright: Bool) {
        guard let root = layer else { return }
        let text = String(raw.replacingOccurrences(of: "\n", with: " ").prefix(Self.longest))
        let letters = text.map(String.init)
        guard !letters.isEmpty else { return }
        busy.insert(column)
        let scale = window?.backingScaleFactor ?? 2
        let width = Self.columnWidth
        let height = CGFloat(letters.count) * Self.lineHeight
        let color = bright ? rainColor : rainColor.withAlphaComponent(0.55)

        let fall = CALayer()
        fall.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let body = CATextLayer()
        body.frame = fall.bounds
        body.string = NSAttributedString(string: letters.dropLast().joined(separator: "\n"), attributes: Self.attributes(color))
        body.contentsScale = scale
        body.alignmentMode = .center
        body.isWrapped = false
        let fade = CAGradientLayer()
        fade.frame = body.bounds
        Self.gradualFade(fade, over: 0.75)
        fade.startPoint = CGPoint(x: 0.5, y: 1)
        fade.endPoint = CGPoint(x: 0.5, y: 0)
        body.mask = fade
        fall.addSublayer(body)

        // The newest letter, at the foot, nearly white.
        let head = CATextLayer()
        head.frame = CGRect(x: 0, y: 0, width: width, height: Self.lineHeight)
        head.string = NSAttributedString(string: letters.last ?? "",
                                         attributes: Self.attributes(rainColor.blended(withFraction: 0.75, of: .white) ?? .white))
        head.contentsScale = scale
        head.alignmentMode = .center
        fall.addSublayer(head)

        let x = CGFloat(column) * width + width / 2
        let from = CGPoint(x: x, y: root.bounds.height + height / 2)
        let to = CGPoint(x: x, y: -height / 2)
        let speed = CGFloat.random(in: bright ? 90...150 : 45...130)
        let duration = Double((from.y - to.y) / speed)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fall.position = to
        root.addSublayer(fall)
        CATransaction.setCompletionBlock { [weak self] in
            fall.removeFromSuperlayer()
            guard let self, self.running else { return }
            self.busy.remove(column)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0...2.5)) { [weak self] in self?.drop(in: column) }
        }
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: from)
        move.toValue = NSValue(point: to)
        move.duration = duration
        move.timingFunction = CAMediaTimingFunction(name: .linear)
        fall.add(move, forKey: "rain")
        CATransaction.commit()
    }

    /// Clear to solid over the first `span`, eased through many steps.
    private static func gradualFade(_ fade: CAGradientLayer, over span: CGFloat) {
        let steps = 12
        var colors: [CGColor] = []
        var locations: [NSNumber] = []
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let eased = t * t * (3 - 2 * t)
            colors.append(NSColor.black.withAlphaComponent(eased).cgColor)
            locations.append(NSNumber(value: Double(t * span)))
        }
        colors.append(NSColor.black.cgColor)
        locations.append(1)
        fade.colors = colors
        fade.locations = locations
    }

    private static func attributes(_ color: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }
}
