// ManuscriptView.swift — the Living Manuscript's editorial style: each
// prompt in a serif, the answer beneath it as it is written, a quiet line
// saying what happened; older exchanges drift up and fade.

import SwiftUI
import ModelCheck

struct ManuscriptView: View {
    let live: LiveState
    let ink: Color
    let privacy: Bool
    var palette: RetroPalette? = nil
    var inspect: (Exchange) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 34) {
                    Color.clear.frame(height: 160)
                    ForEach(live.exchanges.suffix(30)) { exchange in
                        block(exchange).id(exchange.id).onTapGesture { inspect(exchange) }
                    }
                    if let current = live.current {
                        block(current).id("current")
                    }
                    Color.clear.frame(height: 220)
                }
                .frame(maxWidth: 760)
                .retroGlow(palette)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 40)
            }
            .scrollIndicators(.hidden)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.35),
                                         .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .onChange(of: live.tick) { _, _ in withAnimation(.easeInOut(duration: 0.8)) { proxy.scrollTo("current", anchor: .bottom) } }
            .onChange(of: live.current?.answer) { _, _ in proxy.scrollTo("current", anchor: .bottom) }
        }
    }

    private func block(_ exchange: Exchange) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(meta(exchange))
                .font(.system(size: 11, weight: .medium, design: .default))
                .textCase(.uppercase)
                .tracking(1.2)
                .opacity(0.5)
            Text(privacy && exchange.isSensitive ? "A question on a contested subject." : exchange.prompt)
                .font(.system(size: palette == nil ? 24 : 20, weight: .regular, design: palette == nil ? .serif : .monospaced))
                .lineSpacing(4)
            Text(exchange.answer.isEmpty ? "…" : exchange.answer)
                .font(.system(size: palette == nil ? 17 : 15, design: palette == nil ? .serif : .monospaced))
                .italic(palette == nil)
                .foregroundStyle(palette?.lineColor ?? ink)
                .opacity(0.8)
                .lineLimit(exchange.finished ? 8 : nil)
            if let plain = exchange.plain {
                Text(plain).font(.system(size: 13)).opacity(0.55)
            }
        }
    }

    private func meta(_ exchange: Exchange) -> String {
        var parts = [exchange.module == .values && exchange.part.hasPrefix("w2") ? "the same statement, negated" : moduleWord(exchange.module)]
        if exchange.part.hasPrefix("A") { parts.append("first side") }
        if exchange.part.hasPrefix("B") { parts.append("second side") }
        if exchange.part.hasPrefix("framing:pro") || exchange.part.hasPrefix("framing:con") { parts.append("with the asker's view") }
        if !exchange.situation.isEmpty { parts.append(exchange.situation) }
        if exchange.isConfirmation { parts.append("asked again to confirm") }
        return parts.joined(separator: " · ")
    }

    private func moduleWord(_ module: Item.Module) -> String {
        switch module {
        case .facts: "a factual question"
        case .values: "a contested statement"
        case .candour: "a settled question"
        case .dialogue: "a conversation"
        case .work: "a writing task"
        }
    }
}
