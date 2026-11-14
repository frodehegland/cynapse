// ProfileDetailView.swift — File, Accuracy, Candour, Lean, Situations,
// History. Lean as one bar per axis, never a centred marker for "no stable
// position" or "not enough data".

import SwiftUI
import ModelCheck

struct ProfileDetailView: View {
    @Environment(AppModel.self) private var app
    let stored: StoredProfile
    let history: [StoredProfile]
    @Binding var shown: StoredProfile?
    var open: ([String], String) -> Void

    private var profile: Profile { stored.profile }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            section("Lean") {
                ForEach(profile.lean, id: \.axis) { lean in
                    LeanBar(lean: lean, poles: app.bank?.axes[lean.axis])
                        .onTapGesture { open(lean.items, "Lean: \(lean.axis)") }
                }
                Text(profile.limits.first { $0.contains("secular") } ?? "")
                    .font(.caption).foregroundStyle(.secondary)
            }
            section("Work") {
                ForEach(profile.work, id: \.task) { w in
                    Button { open(w.itemIds, "Work: \(w.task)") } label: {
                        Text("\(taskName(w.task)): right on \(w.correct) of \(w.items)" + (w.mirroredDifferences > 0 ? "; treated passages differently depending on the side they argued in \(w.mirroredDifferences)." : "; passages arguing either side treated alike."))
                    }
                    .buttonStyle(.plain)
                }
            }
            section("Situations") {
                Text(profile.consistency.text)
                ForEach(profile.consistency.effects, id: \.condition) { effect in
                    Button { open(effect.items, effect.text) } label: { Text(effect.text) }.buttonStyle(.plain)
                }
                Text("Tried: " + profile.consistency.conditionsTried.map { LiveState.situation(id: $0, conditions: app.bank?.conditions ?? .init()) }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            section("What this can't tell you") {
                ForEach(profile.limits, id: \.self) { Text("• " + $0).foregroundStyle(.secondary) }
            }
            section("History") {
                ForEach(history) { item in
                    HStack {
                        Button(item.date.formatted(date: .abbreviated, time: .shortened) + " · \(item.profile.run.kind.rawValue) · \(item.profile.run.prompts) questions") {
                            shown = item
                        }
                        .buttonStyle(.link)
                        .fontWeight(item == stored ? .semibold : .regular)
                        Spacer()
                        Button("Export…") { app.export(item) }.buttonStyle(.borderless)
                    }
                }
                if history.count >= 2, let changed = changesSince(history[1], history[0]), !changed.isEmpty {
                    Text("Since the check before, answers changed on: \(changed.joined(separator: ", ")).")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            content()
        }
    }

    private func taskName(_ task: String) -> String {
        ["stance": "How two passages relate", "grounded": "Answering only from a passage", "concepts": "Picking out concepts", "summary": "Summarising"][task] ?? task
    }

    /// The repeated questions whose answers differ between two checks.
    private func changesSince(_ before: StoredProfile, _ after: StoredProfile) -> [String]? {
        guard let bank = app.bank else { return nil }
        let a = Scorer.outcomes(ProfileStore.records(of: before), bank: bank)
        let b = Scorer.outcomes(ProfileStore.records(of: after), bank: bank)
        guard !a.isEmpty, !b.isEmpty else { return nil }
        return Drift.changed(since: a, now: b, sentinels: bank.sentinels)
    }
}

/// One axis: its two named ends, and — only when there is a lean to show —
/// a marker with its interval.
struct LeanBar: View {
    let lean: Profile.Lean
    let poles: Bank.AxisPoles?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(lean.axis.capitalized).font(.headline)
                Spacer()
                Text("\(lean.stableItems) consistent · \(lean.unstableItems) inconsistent" + (lean.declinedItems > 0 ? " · \(lean.declinedItems) declined" : ""))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 4).frame(maxHeight: .infinity)
                    Rectangle().fill(.tertiary).frame(width: 1, height: 14).offset(x: w / 2).frame(maxHeight: .infinity)
                    if let value = lean.value, let interval = lean.interval {
                        let x = { (v: Double) in CGFloat((v + 1) / 2) * w }
                        Capsule().fill(.secondary).frame(width: max(2, x(interval[1]) - x(interval[0])), height: 6)
                            .offset(x: x(interval[0])).frame(maxHeight: .infinity)
                        Circle().fill(.primary).frame(width: 12, height: 12)
                            .offset(x: x(value) - 6).frame(maxHeight: .infinity)
                    }
                }
            }
            .frame(height: 18)
            HStack {
                Text(poles?.negative ?? "−").font(.caption)
                Spacer()
                Text(poles?.positive ?? "+").font(.caption)
            }
            .foregroundStyle(.secondary)
            Text(lean.text).font(.callout)
        }
        .contentShape(.rect)
    }
}
