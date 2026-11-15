// ExternalReviewView.swift — at the end of a check's results: Copy For
// External LLM Analysis, Paste External LLM Analysis, and then only where a
// reviewing AI read an answer differently from Cynapse, with every other
// reviewer's reading of that answer beside it (ExternalReview.swift).

import SwiftUI
import AppKit
import ModelCheck

struct ExternalReviewView: View {
    @Environment(AppModel.self) private var app
    let stored: StoredProfile
    let entry: ModelEntry
    /// Opens the evidence for these items.
    var open: ([String], String) -> Void

    @State private var copied = false
    @State private var problem: String?
    /// Cynapse's own reading of each answer, by item.
    @State private var readings: [String: String] = [:]

    private var reviews: [ExternalReview] { stored.profile.externalReviews ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("External reviews").font(.title3.weight(.semibold))
            Text("Ask an online AI you trust to read these answers again, and say where Cynapse read one wrongly. Copy the prompt, paste it into the AI, then copy its whole reply and paste it here. Several AIs can review the same check; each is kept apart, and nothing is rescored.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(copied ? "Copied" : "Copy For External LLM Analysis") { copy() }
                Button("Paste External LLM Analysis") { paste() }
            }
            ForEach(reviews, id: \.reviewer) { review in
                Text(summary(review)).font(.callout)
            }
            if !deviatingIds.isEmpty {
                ForEach(deviatingIds, id: \.self) { id in
                    Button { open([id], "Read differently: \(id)") } label: { deviation(id) }
                        .buttonStyle(.plain)
                }
            } else if !reviews.isEmpty {
                Text("Every reviewer read every answer as Cynapse did.").foregroundStyle(.secondary)
            }
        }
        .task(id: stored.url) { load() }
        .alert("That reply can't be read", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: {
            Text(problem ?? "")
        }
    }

    /// Answers at least one reviewer read differently, in the order asked.
    private var deviatingIds: [String] {
        var ids: [String] = []
        for review in reviews { for d in review.deviations where !ids.contains(d.id) { ids.append(d.id) } }
        return ids
    }

    private func summary(_ review: ExternalReview) -> String {
        "\(review.reviewer), \(review.date): agreed with Cynapse on \(review.agreed) of \(review.asked)"
            + (review.deviations.isEmpty ? "." : "; read \(review.deviations.count) differently.")
    }

    /// Cynapse's reading of one answer, and each reviewer's beside it.
    private func deviation(_ id: String) -> some View {
        let differing = reviews.filter { $0.deviations.contains { $0.id == id } }.map(\.reviewer)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(id).font(.headline)
                Text("read differently by " + differing.joined(separator: ", "))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Assessment.questionable.color)
            }
            Text("Cynapse: " + (readings[id] ?? "—")).foregroundStyle(.secondary)
            ForEach(reviews, id: \.reviewer) { review in
                if let r = review.readings.first(where: { $0.id == id }) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(r.agrees == false ? Assessment.questionable.color : Color.clear)
                            .overlay(Circle().stroke(r.agrees == false ? .clear : Color.secondary.opacity(0.5)))
                            .frame(width: 8, height: 8)
                        Text("\(review.reviewer): " + text(r))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
        .contentShape(.rect)
    }

    private func text(_ r: ExternalReview.Reading) -> String {
        switch r.agrees {
        case true: return "reads it as Cynapse does."
        case false: return [r.yourReading, r.why].compactMap { $0 }.joined(separator: " — ").nilIfEmpty ?? "reads it differently."
        default: return "couldn't tell" + (r.why.map { ": " + $0 } ?? ".")
        }
    }

    private func load() {
        guard let bank = app.lookupBank else { return }
        let entries = ExternalReviewing.entries(records: ProfileStore.records(of: stored), bank: bank)
        readings = Dictionary(entries.map { ($0.id, $0.reading) }, uniquingKeysWith: { a, _ in a })
    }

    private func copy() {
        guard let prompt = app.reviewPrompt(for: stored) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(3)); copied = false }
    }

    private func paste() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        do { try app.addReview(text, to: stored, entry: entry) } catch { problem = String(describing: error) }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
