// ChangesView.swift — at the top of the results: what changed since the
// previous check of the same kind (Changes.swift). Worse first, in red;
// a position that moved, in its neutral colour; better, in green. If
// nothing changed, it says so, so a re-check never passes unremarked.

import SwiftUI
import ModelCheck

struct ChangesView: View {
    @Environment(AppModel.self) private var app
    let current: StoredProfile
    let previous: StoredProfile
    /// Opens the evidence for these items, from the current check.
    var open: ([String], String) -> Void

    @State private var result: (compared: Int, changes: [ResultChange])?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: symbol).foregroundStyle(tint).font(.title3)
                Text(title).font(.title3.weight(.semibold))
            }
            if let note = filesNote {
                Text(note).font(.callout.weight(.medium)).foregroundStyle(Assessment.questionable.color)
            }
            if let result {
                Text(summary(result)).fixedSize(horizontal: false, vertical: true)
                ForEach(result.changes) { change in
                    Button { open([change.itemId], "Changed: \(change.itemId)") } label: { row(change) }
                        .buttonStyle(.plain)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.7), lineWidth: 1.5))
        .task(id: "\(current.url.path)|\(previous.url.path)") { await compare() }
    }

    private var kindName: String {
        switch current.profile.run.kind {
        case .analysis: "Analysis Check"
        case .full: "Full Character Check"
        default: "Quick Character Check"
        }
    }

    private var title: String {
        guard let result else { return "Comparing with the \(kindName) before…" }
        let when = previous.date.formatted(date: .abbreviated, time: .shortened)
        return result.changes.isEmpty ? "No change since the \(kindName) of \(when)" : "Changed since the \(kindName) of \(when)"
    }

    private var worse: Bool { result?.changes.contains { $0.direction == .worse } == true }
    private var tint: Color {
        guard let result else { return .secondary }
        return result.changes.isEmpty ? Assessment.good.color : worse ? Assessment.wrong.color : Assessment.questionable.color
    }
    private var symbol: String {
        guard let result else { return "clock" }
        return result.changes.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    /// The model itself changed between the two checks.
    private var filesNote: String? {
        let a = previous.profile.model, b = current.profile.model
        if let x = a.sha256, let y = b.sha256, x != y { return "The model's files changed between these checks." }
        if a.provider == "apple", let x = a.runtime?.version, let y = b.runtime?.version, x != y {
            return "macOS was updated between these checks (\(x) → \(y))."
        }
        return nil
    }

    private func summary(_ r: (compared: Int, changes: [ResultChange])) -> String {
        guard !r.changes.isEmpty else { return "All \(r.compared) answers asked in both checks were read the same." }
        let count = { (d: ResultChange.Direction) in r.changes.filter { $0.direction == d }.count }
        let parts = [(count(.worse), "worse"), (count(.better), "better"), (count(.moved), "a position moved")]
            .filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        return "\(r.changes.count) of \(r.compared) answers asked in both checks were read differently: " + parts.joined(separator: ", ") + "."
    }

    private func row(_ c: ResultChange) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(c.direction == .worse ? "Worse" : c.direction == .better ? "Better" : "Moved")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(color(c.direction), in: .capsule)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(c.itemId) · \(c.kind)").font(.headline)
                line("Before", c.before, c.beforeAssessment).foregroundStyle(.secondary)
                line("Now", c.after, c.afterAssessment)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
    }

    private func line(_ label: String, _ text: String, _ a: Assessment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(a == .neutral ? Color.clear : a.color)
                .overlay(Circle().stroke(a == .neutral ? Color.secondary.opacity(0.5) : .clear))
                .frame(width: 8, height: 8)
            Text("\(label): \(text)").fixedSize(horizontal: false, vertical: true)
        }
    }

    private func color(_ d: ResultChange.Direction) -> Color {
        switch d {
        case .worse: Assessment.wrong.color
        case .better: Assessment.good.color
        case .moved: Color.gray
        }
    }

    private func compare() async {
        guard let bank = app.lookupBank else { return }
        let before = ProfileStore.records(of: previous), after = ProfileStore.records(of: current)
        let r = await Task.detached(priority: .userInitiated) { ResultChanges.compare(before: before, after: after, bank: bank) }.value
        result = r
    }
}
