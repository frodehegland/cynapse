// MarkdownReport.swift — a model's results as one Markdown document, to
// keep, share or print: what was checked, what changed since the check
// before, every line of the report with its rating, the external reviews,
// what the check can't tell, and every question asked plainly with the
// model's exact answer and how Cynapse read it.

import Foundation

public enum MarkdownReport {

    /// One check to report: its profile, its transcript, and the check of
    /// the same kind before it, if any.
    public struct Check: Sendable {
        public var profile: Profile
        public var records: [Record]
        public var previous: (profile: Profile, records: [Record])?
        public init(profile: Profile, records: [Record], previous: (profile: Profile, records: [Record])? = nil) {
            self.profile = profile; self.records = records; self.previous = previous
        }
    }

    public static func make(model: String, checks: [Check], bank: Bank, now: Date = Date()) -> String {
        var out: [String] = []
        out.append("# Cynapse report: \(model)")
        out.append("")
        out.append("Written by [Cynapse](https://github.com/frodehegland/cynapse) on \(day(now)). A profile, not a verdict: no overall score is given, and a position on a contested question is never rated. Every question, rule and prompt is published with the source.")
        if checks.count > 1 {
            out.append("")
            out.append("**Contents:** " + checks.map { "[\(title($0.profile))](#\(slug(title($0.profile))))" }.joined(separator: " · "))
        }
        for check in checks { out += section(check, bank: bank) }
        out.append("")
        out.append("---")
        out.append("")
        out.append("Ratings: **good**, **acceptable**, **questionable**, **wrong** (or a serious warning); *position* means a position on a contested question, never rated. Each answer was read by plain rules on the Mac that ran the check; judges and external reviews, where shown, are kept apart and never replace those readings.")
        return out.joined(separator: "\n") + "\n"
    }

    static func title(_ p: Profile) -> String {
        switch p.run.kind {
        case .analysis: "Analysis Check"
        case .full: "Full Character Check"
        case .weekly: "Weekly re-check"
        case .quick: "Quick Character Check"
        }
    }

    static func section(_ check: Check, bank: Bank) -> [String] {
        let p = check.profile
        var out: [String] = ["", "## \(title(p))", ""]
        // What was checked.
        let when = ISO8601DateFormatter().date(from: p.createdAt).map(day) ?? p.createdAt
        out.append("- **When:** \(when); \(p.run.prompts) requests\(p.run.completed ? "" : ", not completed").")
        out.append("- **Model:** \(identity(p.model))")
        out.append("- **Questions:** \(p.bank.id) \(p.bank.version) (\(p.bank.kind))" + (p.bank.unsigned == true ? ", a draft not yet signed." : ", signed and published."))
        if let own = p.bank.ownItems, !own.isEmpty { out.append("- **Your own questions included:** \(own.count), written with an AI; not part of the signed set.") }

        // What changed.
        if let previous = check.previous {
            let r = ResultChanges.compare(before: previous.records, after: check.records, bank: bank)
            let since = ISO8601DateFormatter().date(from: previous.profile.createdAt).map(day) ?? previous.profile.createdAt
            out += ["", "### Changed since the \(title(p)) of \(since)", ""]
            if previous.profile.model.sha256 != nil, previous.profile.model.sha256 != p.model.sha256 {
                out += ["**The model's files changed between these checks.**", ""]
            }
            if r.changes.isEmpty {
                out.append("No change: all \(r.compared) answers asked in both checks were read the same.")
            } else {
                out.append("\(r.changes.count) of \(r.compared) answers asked in both checks were read differently.")
                out.append("")
                for c in r.changes {
                    out.append("- **\(c.direction.rawValue.capitalized): \(c.itemId)** (\(c.kind))")
                    out.append("  - Before: \(c.before) — \(word(c.beforeAssessment))")
                    out.append("  - Now: \(c.after) — \(word(c.afterAssessment))")
                }
            }
        }

        // The report, line by line, under its headings.
        out += ["", "### Results"]
        var heading = ""
        for line in p.reportLines() {
            if line.heading != heading {
                heading = line.heading
                out += ["", "**\(heading)**", ""]
            }
            out.append("- \(line.text) — *\(word(line.assessment))*" + (line.items.isEmpty ? "" : " (\(line.items.joined(separator: ", ")))"))
        }

        // External reviews: only where a reviewer read an answer differently.
        if let reviews = p.externalReviews, !reviews.isEmpty {
            out += ["", "### External reviews", ""]
            for r in reviews {
                out.append("- **\(r.reviewer)** (\(r.date)): agreed with Cynapse's reading of \(r.agreed) of \(r.asked) answers" + (r.deviations.isEmpty ? "." : "; read \(r.deviations.count) differently."))
            }
            let ids = reviews.flatMap { $0.deviations.map(\.id) }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            for id in ids {
                out += ["", "**\(id)**, read differently by " + reviews.filter { $0.deviations.contains { $0.id == id } }.map(\.reviewer).joined(separator: ", "), ""]
                for r in reviews {
                    guard let reading = r.readings.first(where: { $0.id == id }) else { continue }
                    let text = reading.agrees == true ? "reads it as Cynapse does."
                        : reading.agrees == false ? [reading.yourReading, reading.why].compactMap { $0 }.joined(separator: " — ")
                        : "couldn't tell" + (reading.why.map { ": " + $0 } ?? ".")
                    out.append("- \(r.reviewer): \(text)")
                }
            }
        }

        out += ["", "### What this can't tell you", ""]
        out += p.limits.map { "- " + $0 }

        // Every answer, as asked plainly.
        let entries = ExternalReviewing.entries(records: check.records, bank: bank)
        if !entries.isEmpty {
            out += ["", "### Every question, as asked plainly", ""]
            out.append("The other situations each question was asked in (dates, contexts, long conversations) are in the transcript, which Cynapse can export.")
            for e in entries {
                out += ["", "#### \(e.id) · \(e.kind)", ""]
                for (asked, answer) in e.exchanges {
                    out.append("> **Asked:** " + asked.replacingOccurrences(of: "\n", with: "\n> "))
                    out.append(">")
                    out.append("> **Answer:** " + answer.replacingOccurrences(of: "\n", with: "\n> "))
                    out.append("")
                }
                out.append("**Cynapse read:** \(e.reading)")
            }
        }
        return out
    }

    static func identity(_ m: ModelIdentity) -> String {
        switch m.provider {
        case "local": "\(m.name), the exact files checked (SHA-256 \(m.sha256 ?? "–"))" + (m.quantisation.map { ", \($0)" } ?? "") + "."
        case "apple": "Apple's built-in model, in \(m.runtime?.version ?? "this version of macOS")."
        case "cloud": "\(m.name), a cloud model, as its service answered" + (m.settings["checkedOn"].map { " on \($0)" } ?? "") + ". It can change without notice."
        default: m.name
        }
    }

    static func word(_ a: Assessment) -> String {
        switch a {
        case .good: "good"
        case .ok: "acceptable"
        case .questionable: "questionable"
        case .wrong: "wrong"
        case .neutral: "position"
        }
    }

    static func day(_ date: Date) -> String {
        date.formatted(date: .long, time: .shortened)
    }

    /// A heading's anchor, as GitHub makes it.
    static func slug(_ heading: String) -> String {
        String(heading.lowercased().unicodeScalars.compactMap { c -> Character? in
            if CharacterSet.alphanumerics.contains(c) || c == "-" { return Character(c) }
            return c == " " ? "-" : nil
        })
    }
}
