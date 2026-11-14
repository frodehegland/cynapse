// ProfileCardView.swift — the profile, one point to a line (Report.swift),
// each line opening the questions and answers behind it.

import SwiftUI
import ModelCheck

struct ProfileCardView: View {
    let profile: Profile
    let status: String
    /// Opens the evidence for these items.
    var open: ([String], String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(fileText)
                .foregroundStyle(status == "changed" ? Color.red : Color.secondary)
                .padding(.bottom, 4)
            // One point to a line, each opening the questions behind it.
            ForEach(Array(profile.reportLines().enumerated()), id: \.offset) { index, line in
                let lines = profile.reportLines()
                let showHeading = index == 0 || lines[index - 1].heading != line.heading
                Button { open(line.items, line.heading) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(showHeading ? line.heading : "")
                            .font(.headline)
                            .frame(width: 96, alignment: .leading)
                        Text(line.text).frame(maxWidth: .infinity, alignment: .leading)
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
