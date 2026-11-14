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
                render(LiveSnapshot().environment(app), "live-connections-running", folder)
                while app.runningEntry != nil { try? await Task.sleep(for: .milliseconds(300)) }
            }
            if app.live.exchanges.isEmpty { app.replayLatest() }
            render(LiveSnapshot().environment(app), "live-connections", folder)
            render(LiveSnapshot(clusters: true).environment(app), "live-connections-clusters", folder)
            render(ProfileCardView(profile: app.live.profile ?? app.profiles[entry.id]!.first!.profile, status: "checked", close: {}) { _, _ in }
                    .padding(20).frame(width: 760).environment(app), "card", folder, size: CGSize(width: 760, height: 900))
            render(ModelDetailView(entry: entry).environment(app).frame(width: 900, height: 1500), "detail", folder, size: CGSize(width: 900, height: 1500))
            if let stored = app.profiles[entry.id]?.first {
                let records = ProfileStore.records(of: stored)
                print("panel check: profile \(stored.url.lastPathComponent); transcript exists \(FileManager.default.fileExists(atPath: stored.transcriptURL.path)); records \(records.count); accuracy ids \(stored.profile.accuracy.items.count)")
                let line = stored.profile.reportLines().first { $0.text.hasPrefix("Made up") }
                let matching = records.filter { (line?.items ?? []).contains($0.ask.itemId) }
                print("panel check: line items \(line?.items ?? []); matching records \(matching.count); sample record item ids \(Set(records.prefix(20).map(\.ask.itemId)).sorted().prefix(6))")
                let panel = EvidenceView(evidence: Evidence(title: line?.text ?? "", ids: line?.items ?? [], stored: stored), close: {}, scrolls: false).environment(app)
                let host = NSHostingView(rootView: panel.frame(width: 480, height: 900))
                host.frame = NSRect(x: 0, y: 0, width: 480, height: 900)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                window.orderBack(nil)
                try? await Task.sleep(for: .seconds(2))
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("panel.png"))
                }
            }
            // A clicked answer in Connections: a wrong one if there is one.
            let ratings = app.live.assessments(bank: app.bank)
            if let exchange = app.live.exchanges.first(where: { ratings[$0.outcomeKey] == .wrong }) ?? app.live.exchanges.first {
                let pick = ConnectionPick(itemId: exchange.itemId, exchangeKey: exchange.key)
                render(LiveSnapshot(picked: pick).environment(app), "live-connections-picked", folder)
                let host = NSHostingView(rootView: ConnectionPanel(pick: pick, live: app.live, bank: app.bank) {}
                    .environment(\.colorScheme, .dark).frame(width: 480, height: 900))
                host.frame = NSRect(x: 0, y: 0, width: 480, height: 900)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                window.appearance = NSAppearance(named: .darkAqua)
                window.orderBack(nil)
                try? await Task.sleep(for: .seconds(2))
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("connection-panel.png"))
                }
                print("panel check: picked \(exchange.key)")
            }
            await renderWindow(NewQuestionsView().environment(app), "new-questions", folder, size: CGSize(width: 640, height: 720))
            await renderWindow(GuideView(), "guide", folder, size: CGSize(width: 760, height: 1400))
            print("Wrote snapshots to \(folder.path)")
            exit(0)
        }
    }

    /// Through a real window, for views a plain render can't draw (scroll
    /// views, controls).
    static func renderWindow<V: View>(_ view: V, _ name: String, _ folder: URL, size: CGSize) async {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        try? await Task.sleep(for: .seconds(1.5))
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(name).png"))
        }
        window.orderOut(nil)
    }

    static func render<V: View>(_ view: V, _ name: String, _ folder: URL, size: CGSize = CGSize(width: 1280, height: 800)) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { print("couldn't render \(name)"); return }
        try? png.write(to: folder.appendingPathComponent("\(name).png"))
    }
}

/// The Live View, for snapshots.
struct LiveSnapshot: View {
    @Environment(AppModel.self) private var app
    var picked: ConnectionPick? = nil
    var clusters = false
    var body: some View {
        ZStack {
            Color.black
            ConnectionsView(live: app.live, bank: app.bank, picked: picked, fixedClusters: clusters)
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
            .foregroundStyle(Color(red: 0.36, green: 0.44, blue: 0.70))
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}
