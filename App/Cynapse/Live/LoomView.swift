// LoomView.swift — the check's own machinery: the files' fingerprint, the
// questions' signature, and every request as a thread in the loom.
//
// Shows only what exists: judges and the hidden question pool will join
// it when they are built.

import SwiftUI
import ModelCheck

struct LoomView: View {
    let live: LiveState
    let ink: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                drawFingerprint(&context, size: size, t: t)
                drawLoom(&context, size: size, t: t)
            }
        }
    }

    /// The fingerprint, cascading down the left in blocks, and the
    /// signature beneath it.
    private func drawFingerprint(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        let font = Font.system(size: 13, design: .monospaced)
        let x: CGFloat = 60
        var y: CGFloat = size.height * 0.24
        let hash = live.model?.sha256 ?? ""
        let title = hash.isEmpty ? "no files to pin (\(live.model?.provider == "cloud" ? "a cloud model" : "built into macOS"))" : "files pinned · sha256"
        context.draw(Text(title).font(font).foregroundStyle(ink.opacity(0.6)), at: CGPoint(x: x, y: y), anchor: .leading)
        y += 26
        let chunks = stride(from: 0, to: hash.count, by: 8).map { i -> String in
            let start = hash.index(hash.startIndex, offsetBy: i)
            return String(hash[start..<hash.index(start, offsetBy: min(8, hash.count - i))])
        }
        for (i, chunk) in chunks.enumerated() {
            let shimmer = 0.5 + 0.5 * sin(t * 2 - Double(i) * 0.5)
            context.draw(Text(chunk).font(font).foregroundStyle(ink.opacity(0.35 + 0.5 * shimmer)),
                         at: CGPoint(x: x + CGFloat(i % 4) * 86, y: y + CGFloat(i / 4) * 22), anchor: .leading)
        }
        y += CGFloat((chunks.count + 3) / 4) * 22 + 30
        if let bank = live.bank {
            context.draw(Text("questions \(bank.id) \(bank.version)").font(font).foregroundStyle(ink.opacity(0.6)), at: CGPoint(x: x, y: y), anchor: .leading)
            context.draw(Text("Ed25519 signature verified").font(font).foregroundStyle(ink.opacity(0.85)), at: CGPoint(x: x, y: y + 22), anchor: .leading)
        }
    }

    /// Every request is a cell: dim until asked, full once answered. A
    /// question asked again to confirm a difference sits in its own row.
    private func drawLoom(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        let left = size.width * 0.42, right = size.width - 60
        let top = size.height * 0.2
        let total = max(live.planned, 1)
        let columns = 24
        let cell = min((right - left) / CGFloat(columns), 18)
        for index in 0..<total {
            let row = index / columns, column = index % columns
            let rect = CGRect(x: left + CGFloat(column) * cell, y: top + CGFloat(row) * cell, width: cell - 3, height: cell - 3)
            let answered = index < live.done
            let asking = index == live.done && live.running
            let pulse = asking ? 0.5 + 0.5 * sin(t * 6) : 0
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(ink.opacity(answered ? 0.75 : 0.08 + 0.6 * pulse)))
        }
        // The thread being woven: the current request, in words.
        if let current = live.current {
            let y = top + CGFloat((total + columns - 1) / columns) * cell + 34
            context.draw(Text(current.situation.isEmpty ? "asked plainly" : current.situation).font(.system(size: 12, design: .monospaced)).foregroundStyle(ink.opacity(0.6)),
                         at: CGPoint(x: left, y: y), anchor: .leading)
            if current.isConfirmation {
                context.draw(Text("asked again, to see whether a difference holds").font(.system(size: 12, design: .monospaced)).foregroundStyle(ink.opacity(0.85)),
                             at: CGPoint(x: left, y: y + 20), anchor: .leading)
            }
        }
    }
}
