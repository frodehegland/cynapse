// Snapshot.swift — `Cynapse --snapshot <model> <folder>`: runs a quick check
// and renders the main screens to PNG files, so the interface can be
// looked at without a person at the screen (used to check Cynapse itself).

import SwiftUI
import AppKit
import ModelCheck

@MainActor
enum Snapshot {

    static var requested: Bool { CommandLine.arguments.contains("--snapshot") }

    static func run(_ app: AppModel) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), args.count > i + 2 else { print("Usage: --snapshot <model> <folder>"); exit(2) }
        let wanted = args[i + 1].lowercased()
        let folder = URL(fileURLWithPath: args[i + 2], isDirectory: true)
        Task { @MainActor in
            while !app.fingerprinting.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            guard let entry = app.entries.first(where: { wanted == "apple" ? $0.kind == .apple : $0.name.lowercased().contains(wanted) }) else {
                print("No model matching \(wanted)"); exit(2)
            }
            app.selection = entry.id
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if app.profiles[entry.id]?.isEmpty ?? true || args.contains("--fresh") {
                app.startCheck(entry, mode: .quick)
                // Mid-run pictures, once there is something to show.
                while app.runningEntry != nil && app.live.done < 120 { try? await Task.sleep(for: .milliseconds(300)) }
                render(LiveSnapshot(look: .manuscript).environment(app), "live-manuscript-running", folder)
                render(LiveSnapshot(look: .constellation).environment(app), "live-constellation-running", folder)
                render(LiveSnapshot(look: .loom).environment(app), "live-loom-running", folder)
                while app.runningEntry != nil { try? await Task.sleep(for: .milliseconds(300)) }
            }
            if app.live.exchanges.isEmpty { app.replayLatest() }
            render(LiveSnapshot(look: .synapses).environment(app), "live-synapses", folder)
            render(LiveSnapshot(look: .constellation).environment(app), "live-constellation-done", folder)
            render(ProfileCardView(profile: app.live.profile ?? app.profiles[entry.id]!.first!.profile, status: "checked") { _, _ in }
                    .padding(20).frame(width: 760).environment(app), "card", folder, size: CGSize(width: 760, height: 900))
            render(ModelDetailView(entry: entry).environment(app).frame(width: 900, height: 1500), "detail", folder, size: CGSize(width: 900, height: 1500))
            print("Wrote snapshots to \(folder.path)")
            exit(0)
        }
    }

    static func render<V: View>(_ view: V, _ name: String, _ folder: URL, size: CGSize = CGSize(width: 1280, height: 800)) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { print("couldn't render \(name)"); return }
        try? png.write(to: folder.appendingPathComponent("\(name).png"))
    }
}

/// The Live View with a fixed look, for snapshots (the real one cycles).
struct LiveSnapshot: View {
    @Environment(AppModel.self) private var app
    let look: LiveLook
    var body: some View {
        ZStack {
            Color.black
            switch look {
            case .synapses: SynapseView(live: app.live, bank: app.bank)
            case .manuscript: ManuscriptView(live: app.live, ink: .white, privacy: false) { _ in }
            case .constellation: ConstellationView(live: app.live, bank: app.bank, ink: .white)
            case .loom: LoomView(live: app.live, ink: .white)
            }
            VStack {
                HStack {
                    VStack(alignment: .leading) {
                        Text(app.live.model?.name ?? "").font(.system(size: 14, weight: .semibold, design: .monospaced))
                        if let bank = app.live.bank { Text("questions \(bank.version) · signature verified").font(.system(size: 12, design: .monospaced)) }
                    }
                    Spacer()
                    Text("\(app.live.done) of \(app.live.planned)").font(.system(size: 14, weight: .semibold, design: .monospaced))
                }
                Spacer()
                HStack {
                    VStack(alignment: .leading) {
                        ForEach(Array(app.live.ticker.suffix(3).enumerated()), id: \.offset) { Text($0.element).font(.system(size: 12, design: .monospaced)) }
                    }
                    Spacer()
                }
            }
            .padding(24)
            .foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}
