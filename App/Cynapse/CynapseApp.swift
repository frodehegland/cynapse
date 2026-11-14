// CynapseApp.swift — Cynapse: see how an AI model behaves, and check it
// yourself. Open source: github.com/frodehegland/cynapse

import SwiftUI

@main
struct CynapseApp: App {
    @State private var app = AppModel()

    init() {
        if Headless.requested { Headless.run(app) }
        if Snapshot.requested { Snapshot.run(app) }
    }

    var body: some Scene {
        WindowGroup("Cynapse", id: "main") {
            ContentView()
                .environment(app)
                .onOpenURL { app.open($0) }
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .help) {
                Link("Cynapse on GitHub", destination: URL(string: "https://github.com/frodehegland/cynapse")!)
                OpenWindowButton(title: "Cynapse Guide", id: "guide")
                Link("The design brief", destination: URL(string: "https://github.com/frodehegland/cynapse/blob/main/docs/build-brief-v2.md")!)
            }
            CommandMenu("Questions") {
                OpenWindowButton(title: "See the Questions", id: "questions")
                    .keyboardShortcut("q", modifiers: [.command, .shift])
                OpenWindowButton(title: "Write New Questions with an AI…", id: "questions") {
                    // The window first, then its sheet.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: .writeNewQuestions, object: nil)
                    }
                }
            }
        }

        Window("Live View", id: "live") {
            LiveView()
                .environment(app)
        }
        .windowStyle(.hiddenTitleBar)

        Window("The Questions", id: "questions") {
            QuestionsView()
                .environment(app)
        }

        Window("Cynapse Guide", id: "guide") {
            GuideView()
        }

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}

private struct OpenWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    let title: String
    let id: String
    var then: () -> Void = {}
    var body: some View { Button(title) { openWindow(id: id); then() } }
}
