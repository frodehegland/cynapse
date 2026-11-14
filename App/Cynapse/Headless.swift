// Headless.swift — `Cynapse --headless-check <model> [--full]` runs a check
// without the window and prints the profile: for checking Cynapse itself,
// and for checking a model from a script. <model> is part of a model's name
// as listed in the app, or "apple". Use `--list` to see the names.

import Foundation
import AppKit
import ModelCheck

@MainActor
enum Headless {

    static var requested: Bool {
        ["--headless-check", "--list", "--download"].contains { CommandLine.arguments.contains($0) }
    }

    static func run(_ app: AppModel) {
        let args = CommandLine.arguments
        Task { @MainActor in
            // Fingerprints are worked out in the background; wait for them.
            while !app.fingerprinting.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            if let i = args.firstIndex(of: "--download"), args.count > i + 1 {
                print("Downloading \(args[i + 1])…")
                await app.download(args[i + 1])
                if let problem = app.downloadProblem { print(problem); exit(1) }
                print("Downloaded.")
                if !args.contains("--headless-check") { exit(0) }
            }
            if args.contains("--list") {
                for entry in app.entries { print("\(entry.kindLabel): \(entry.name)  [\(app.status(of: entry))]") }
                if app.entries.isEmpty { print("No models found.") }
                exit(0)
            }
            guard let index = args.firstIndex(of: "--headless-check"), args.count > index + 1 else {
                print("Usage: Cynapse --headless-check <model> [--full]"); exit(2)
            }
            let wanted = args[index + 1].lowercased()
            guard let entry = app.entries.first(where: { wanted == "apple" ? $0.kind == .apple : $0.name.lowercased().contains(wanted) }) else {
                print("No model matching “\(wanted)”. Try --list."); exit(2)
            }
            if let problem = app.bankProblem { print(problem); exit(1) }
            let mode: RunMode = args.contains("--full") ? .full : .quick
            print("Checking \(entry.name) (\(mode.rawValue))…")
            let started = Date()
            app.startCheck(entry, mode: mode)
            if let problem = app.runProblem { print(problem); exit(1) }
            var lastShown = 0
            while app.runningEntry != nil {
                try? await Task.sleep(for: .milliseconds(500))
                if app.live.done != lastShown, app.live.done % 20 == 0 {
                    lastShown = app.live.done
                    print("  \(app.live.done) of \(app.live.planned)")
                }
            }
            guard let stored = app.profiles[entry.id]?.first, stored.date >= started.addingTimeInterval(-5) else {
                print(app.runProblem ?? "The check didn't finish."); exit(1)
            }
            let p = stored.profile
            print("Accuracy: right on \(p.accuracy.correct) of \(p.accuracy.answerable); invented \(p.accuracy.invented) of \(p.accuracy.unanswerable).")
            print("Candour: held \(p.candour.held) of \(p.candour.items)" + (p.candour.declined > 0 ? ", declined \(p.candour.declined)." : "."))
            for lean in p.lean { print("Lean: \(lean.text)") }
            print(p.consistency.text)
            for flag in p.flags { print("  ! \(flag.text)") }
            print("Profile: \(stored.url.path)")
            print(String(format: "Took %.0f seconds.", Date().timeIntervalSince(started)))
            exit(0)
        }
    }
}
