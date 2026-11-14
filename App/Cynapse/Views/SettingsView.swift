// SettingsView.swift — the Live View's look, and the person's cloud keys.

import SwiftUI
import ModelCheckModels

struct SettingsView: View {
    var body: some View {
        TabView {
            LiveSettingsView().tabItem { Label("Live View", systemImage: "sparkles.tv") }
            KeysView().tabItem { Label("Cloud Keys", systemImage: "key") }
        }
        .frame(width: 500)
        .padding()
    }
}

struct LiveSettingsView: View {
    @AppStorage(LiveSettings.style) private var style = "random"
    @AppStorage(LiveSettings.cycleSeconds) private var cycleSeconds = 90
    @AppStorage(LiveSettings.density) private var density = "standard"
    @AppStorage(LiveSettings.manuscriptStyle) private var manuscriptStyle = "rain"
    @AppStorage(LiveSettings.privacy) private var privacy = false
    @AppStorage(LiveSettings.theme) private var theme = "system"

    var body: some View {
        Form {
            Picker("Look", selection: $style) {
                Text("Change by itself").tag("random")
                ForEach(LiveLook.allCases) { Text($0.title).tag($0.rawValue) }
            }
            if style == "random" {
                Picker("Change", selection: $cycleSeconds) {
                    Text("When a new kind of question begins").tag(0)
                    Text("Every minute").tag(60)
                    Text("Every 90 seconds").tag(90)
                    Text("Every 3 minutes").tag(180)
                }
            }
            Picker("Manuscript style", selection: $manuscriptStyle) {
                Text("Rain (from Author's Matrix)").tag("rain")
                Text("Scrolling page").tag("scroll")
            }
            Picker("Information", selection: $density) {
                Text("Pictures only").tag("ambient")
                Text("Standard").tag("standard")
                Text("Everything, with request codes").tag("diagnostic")
            }
            Toggle("Hide the wording of charged questions", isOn: $privacy)
            Text("For a shared or office screen: contested questions show as “a question on a contested subject”.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Colours", selection: $theme) {
                Text("Follow the system").tag("system")
                Text("Paper").tag("paper")
                Text("Obsidian").tag("obsidian")
            }
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
