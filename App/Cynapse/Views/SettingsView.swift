// SettingsView.swift — the Live View, re-checks, judges, and the person's cloud keys.

import SwiftUI
import ModelCheckModels

struct SettingsView: View {
    var body: some View {
        TabView {
            LiveSettingsView().tabItem { Label("Live View", systemImage: "sparkles.tv") }
            ChecksSettingsView().tabItem { Label("Re-checks", systemImage: "calendar") }
            JudgesSettingsView().tabItem { Label("Judges", systemImage: "person.3") }
            KeysView().tabItem { Label("Cloud Keys", systemImage: "key") }
        }
        .frame(width: 500)
        .padding()
    }
}

struct LiveSettingsView: View {
    @AppStorage(LiveSettings.density) private var density = "standard"
    @AppStorage(LiveSettings.privacy) private var privacy = false
    @AppStorage(LiveSettings.retro) private var retro = false
    @AppStorage(LiveSettings.retroPalette) private var retroPalette = "random"
    @AppStorage(LiveSettings.fullScreen) private var fullScreen = true

    var body: some View {
        Form {
            Toggle("Open in full screen", isOn: $fullScreen)
            Toggle("Retro", isOn: $retro)
            if retro {
                Picker("Retro colours", selection: $retroPalette) {
                    Text("A different one each time").tag("random")
                    ForEach(RetroPalette.all) { Text($0.name).tag($0.name) }
                }
            }
            Picker("Information", selection: $density) {
                Text("Pictures only").tag("ambient")
                Text("Standard").tag("standard")
                Text("Everything, with request codes").tag("diagnostic")
            }
            Toggle("Hide the wording of charged questions", isOn: $privacy)
            Text("For a shared or office screen: contested questions show as “a question on a contested subject”.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct KeysView: View {
    @State private var keys: [CloudModel.Provider: String] = [:]

    var body: some View {
        Form {
            ForEach(CloudModel.Provider.allCases, id: \.self) { provider in
                SecureField(provider.displayName, text: Binding(
                    get: { keys[provider] ?? "" },
                    set: { keys[provider] = $0; Keychain.setKey($0, for: provider) }))
            }
            Text("Your keys are kept in your Keychain and sent only to their own service. Cynapse has no keys of its own, and never sends anything of yours: only its published questions.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .onAppear {
            for provider in CloudModel.Provider.allCases { keys[provider] = Keychain.key(for: provider) ?? "" }
        }
    }
}

struct ChecksSettingsView: View {
    @AppStorage(WeeklyChecks.enabledKey) private var weekly = true
    @State private var atLogin = WeeklyChecks.opensAtLogin

    var body: some View {
        Form {
            Toggle("Re-check models each week", isOn: $weekly)
            Text("A short re-check of each downloaded model and Apple's, on mains power, while Cynapse is open. You hear about it only if a model's answers have changed. Cloud models aren't re-checked automatically, since each check is paid for with your key.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Open Cynapse at login", isOn: $atLogin)
                .onChange(of: atLogin) { _, new in WeeklyChecks.opensAtLogin = new }
        }
        .formStyle(.grouped)
    }
}

struct JudgesSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var chosen: Set<String> = []

    var body: some View {
        Form {
            Section {
                ForEach(app.entries) { entry in
                    Toggle(isOn: Binding(get: { chosen.contains(entry.id) }, set: { on in
                        if on { chosen.insert(entry.id) } else { chosen.remove(entry.id) }
                        app.judgeIDs = Array(chosen)
                    })) {
                        VStack(alignment: .leading) {
                            Text(entry.name)
                            Text(entry.kindLabel + " · " + app.status(of: entry)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!chosen.contains(entry.id) && chosen.count >= 3)
                }
            } footer: {
                Text("Judges read what matching can't: whether an answer presents a position fairly or only mentions it to dismiss it, and whether both sides of a question were argued as strongly. Choose two or three from different labs. No judge is neutral, so each judge's verdicts are shown separately, with how often they agreed; a model never judges itself. A judge should itself have been checked.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onAppear { chosen = Set(app.judgeIDs) }
    }
}
