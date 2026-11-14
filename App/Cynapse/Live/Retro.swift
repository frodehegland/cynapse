// Retro.swift — Author's Retro mode (CanvasViewController+Dream.swift,
// Frode Hegland): one of five palettes, monospaced letters in the
// palette's text colour, lines in its line colour, and a glow.

import SwiftUI
import AppKit

struct RetroPalette: Identifiable, Hashable {
    let name: String
    let line: NSColor
    let text: NSColor
    var id: String { name }
    var lineColor: Color { Color(nsColor: line) }
    var textColor: Color { Color(nsColor: text) }

    static let ember = RetroPalette(name: "Ember",
                                    line: NSColor(calibratedRed: 1, green: 0.08, blue: 0.08, alpha: 1),
                                    text: NSColor(calibratedRed: 1, green: 0.55, blue: 0.05, alpha: 1))
    static let terminal = RetroPalette(name: "Terminal",
                                       line: NSColor(calibratedRed: 0.1, green: 0.9, blue: 0.25, alpha: 1),
                                       text: NSColor(calibratedRed: 1, green: 0.92, blue: 0.15, alpha: 1))
    static let cyberpunk = RetroPalette(name: "Cyberpunk",
                                        line: NSColor(calibratedRed: 0, green: 0.85, blue: 1, alpha: 1),
                                        text: NSColor(calibratedRed: 1, green: 0.15, blue: 0.85, alpha: 1))
    static let amberCRT = RetroPalette(name: "Amber CRT",
                                       line: NSColor(calibratedRed: 1, green: 0.6, blue: 0, alpha: 1),
                                       text: NSColor(calibratedRed: 1, green: 0.78, blue: 0.25, alpha: 1))
    static let ice = RetroPalette(name: "Ice",
                                  line: NSColor(calibratedRed: 0.25, green: 0.55, blue: 1, alpha: 1),
                                  text: NSColor(calibratedRed: 0.65, green: 0.85, blue: 1, alpha: 1))

    static let all: [RetroPalette] = [.ember, .terminal, .cyberpunk, .amberCRT, .ice]
    static func named(_ name: String) -> RetroPalette { all.first { $0.name == name } ?? all.randomElement()! }
}

extension View {
    /// The Retro glow: a soft halo in the palette's colour.
    @ViewBuilder func retroGlow(_ palette: RetroPalette?) -> some View {
        if let palette {
            self.shadow(color: palette.textColor.opacity(0.9), radius: 5)
        } else {
            self
        }
    }
}

/// Fills the whole screen, or leaves it: the window the view sits in.
struct FullScreenControl: NSViewRepresentable {
    @Binding var request: Bool
    var fullScreenAtStart: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.collectionBehavior.insert(.fullScreenPrimary)
            if fullScreenAtStart, !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard request else { return }
        DispatchQueue.main.async {
            view.window?.toggleFullScreen(nil)
            request = false
        }
    }
}
