// ProfileCardView.swift — the four plain lines, the situations line and the
// limits. Every line opens the questions and answers behind it.

import SwiftUI
import ModelCheck

struct ProfileCardView: View {
    let profile: Profile
    let status: String
    /// Opens the evidence for these items.
    var open: ([String], String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            line("File", fileText, ids: [])
                .foregroundStyle(status == "changed" ? Color.red : Color.primary)
            line("Accuracy", accuracyText, ids: profile.accuracy.items)
            line("Candour", candourText, ids: profile.candour.itemIds)
            line("Lean", leanText, ids: profile.lean.flatMap(\.items))
            Divider()
            Button { open(profile.consistency.effects.flatMap(\.items), "Situations") } label: {
                Text(profile.consistency.effects.first?.text ?? profile.consistency.text)
            }
            .buttonStyle(.plain)
            .disabled(profile.consistency.effects.isEmpty)
            ForEach(Array(profile.flags.filter { $0.module != "consistency" }.enumerated()), id: \.offset) { _, flag in
                Button { open(flag.items, flag.text) } label: { Text(flag.text) }.buttonStyle(.plain)
            }
            if let judges = profile.judges, !judges.isEmpty {
                Button { open(judges.flatMap { $0.verdicts.map(\.itemId) }, "Judges") } label: {
                    Text(judgeText(judges))
                }
                .buttonStyle(.plain)
            }
            Text(dateLine).foregroundStyle(.secondary)
            Text(profile.limits.first ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private func line(_ title: String, _ text: String, ids: [String]) -> some View {
        Button { open(ids, title) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).font(.headline).frame(width: 90, alignment: .leading)
                Text(text).frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(ids.isEmpty)
    }

    private var fileText: String {
        switch profile.model.provider {
        case "local":
            if status == "changed" { return "This model's files have changed since this check. Check it again before relying on it." }
            return "These are the exact files that were checked (fingerprint \(profile.model.sha256?.prefix(12) ?? "–")…)."
        case "apple": return "Apple's built-in model, as it is in \(profile.model.runtime?.version ?? "this version of macOS")."
        case "cloud": return "A cloud model, as its service answered on \(profile.model.settings["checkedOn"] ?? "the day of the check"). It can change without notice."
        default: return profile.model.name
        }
    }

    private var accuracyText: String {
        let a = profile.accuracy
        var text = "Right on \(a.correct) of \(a.answerable) checkable questions. Made up an answer to \(a.invented) of \(a.unanswerable) questions that have none."
        if a.evidenceItems > 0 { text += " Gave both main positions on \(a.evidenceBalanced) of \(a.evidenceItems) contested questions." }
        return text
    }

    private var candourText: String {
        let c = profile.candour
        var text = "Kept its answer when told what the asker believed in \(c.held) of \(c.items) cases."
        if c.declined > 0 { text += " Declined to answer \(c.declined)." }
        if c.ladders > 0 { text += " Gave way to pressure alone in \(c.changedUnderPressureOnly) of \(c.ladders) conversations." }
        return text
    }

    private var leanText: String {
        profile.lean.map(\.text).joined(separator: " ")
    }

    private func judgeText(_ judges: [JudgeReport]) -> String {
        let each = judges.map { "\($0.judge.name) found \($0.positionsFair) of \($0.positions) positions fairly presented and \($0.pairsEven) of \($0.pairs) two-sided requests evenly argued" }
        return each.joined(separator: "; ") + "." + (profile.judgeAgreement.map { " They agreed on \($0.agreed) of \($0.asked) readings." } ?? "")
    }

    private var dateLine: String {
        let date = ISO8601DateFormatter().date(from: profile.createdAt).map { $0.formatted(date: .long, time: .shortened) } ?? profile.createdAt
        let kind = ["full": "Full check", "quick": "Quick check", "weekly": "Weekly re-check"][profile.run.kind.rawValue] ?? "Check"
        return "\(kind), \(date). \(profile.run.prompts) questions asked."
    }
}
