// ProfileCardView.swift — the profile, one point to a line (Report.swift),
// each line opening the questions and answers behind it.

import SwiftUI
import ModelCheck

struct ProfileCardView: View {
    let profile: Profile
    let status: String
    /// Puts the report away, where it is shown over something (the Live
    /// View); nil where it is part of the page.
    var close: (() -> Void)? = nil
    /// Opens the evidence for these items.
    var open: ([String], String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(fileText)
                    .foregroundStyle(status == "changed" ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let close {
                    Spacer(minLength: 12)
                    Button("Close", systemImage: "xmark") { close() }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .help("Put the report away, to see the network behind (Esc). Report brings it back.")
                }
            }
            .padding(.bottom, 4)
            // One point to a line, each opening the questions behind it.
            ForEach(Array(profile.reportLines().enumerated()), id: \.offset) { index, line in
                let lines = profile.reportLines()
                let showHeading = index == 0 || lines[index - 1].heading != line.heading
                Button { open(line.items, line.text) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(showHeading ? line.heading : "")
                            .font(.headline)
                            .frame(width: 96, alignment: .leading)
                        // Its rating: green good, yellow acceptable, orange
                        // questionable, red wrong or serious; a position on a
                        // contested question is never rated.
                        Circle()
                            .fill(line.assessment == .neutral ? Color.clear : line.assessment.color)
                            .overlay(Circle().stroke(line.assessment == .neutral ? Color.secondary.opacity(0.5) : .clear, lineWidth: 1))
                            .frame(width: 8, height: 8)
                            .help(line.assessment.word.prefix(1).uppercased() + line.assessment.word.dropFirst())
                        Text(line.text)
                            .foregroundStyle(line.isSerious ? Assessment.wrong.color : Color.primary)
                            .underline(!line.items.isEmpty, pattern: .dot, color: Color.secondary.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!line.items.isEmpty)
                .padding(.top, showHeading && index > 0 ? 6 : 0)
            }
            Text(profile.limits.first ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .padding(20)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
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
}
