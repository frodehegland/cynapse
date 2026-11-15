// ExternalReviewTests.swift — the prompt carried to a reviewing AI, and the
// reply read back: only answers that were asked, each reviewer kept apart.

import Foundation
import Testing
import ModelCheck
import ModelCheckStubs

@Suite struct ExternalReviews {

    func checked() async throws -> (Profile, [Record], Bank) {
        let bank = try fixtureBank()
        let model = StubModel(.honest, bank: bank)
        let runner = Runner(bank: bank, model: model, now: fixedNow)
        let records = try await runner.run(.quick)
        let profile = ProfileBuilder.build(records: records, bank: bank, model: model.identity, mode: .quick,
                                           baseline: runner.baseline, createdAt: fixedNow)
        return (profile, records, bank)
    }

    @Test func thePromptHoldsEveryPlainAnswerAndCynapsesReading() async throws {
        let (profile, records, bank) = try await checked()
        let entries = ExternalReviewing.entries(records: records, bank: bank)
        let prompt = ExternalReviewing.prompt(profile: profile, records: records, bank: bank)
        #expect(!entries.isEmpty)
        for entry in entries {
            #expect(prompt.contains("--- \(entry.id) · "))
            #expect(prompt.contains("Cynapse read: \(entry.reading)"))
        }
        #expect(prompt.contains(#""cynapseRight""#))
    }

    @Test func aReplyKeepsOnlyAskedAnswersAndShowsWhereItDiffers() async throws {
        let (_, records, bank) = try await checked()
        let ids = ExternalReviewing.entries(records: records, bank: bank).map(\.id)
        let reply = """
        Here you are:
        ```json
        {"reviewer":"Reviewer One 2","readings":[
          {"id":"\(ids[0])","cynapseRight":false,"yourReading":"It gave a different answer.","why":"It says so."},
          {"id":"\(ids[1])","cynapseRight":true},
          {"id":"\(ids[1])","cynapseRight":false},
          {"id":"not-asked-0001","cynapseRight":false}
        ]}
        ```
        """
        let review = try ExternalReviewing.read(reply, records: records, bank: bank, now: fixedNow)
        #expect(review.reviewer == "Reviewer One 2")
        #expect(review.asked == ids.count)
        #expect(review.readings.count == 2)
        #expect(review.deviations.map(\.id) == [ids[0]])
        #expect(review.agreed == 1)
    }

    @Test func aSecondReviewByTheSameAIReplacesTheFirst() async throws {
        let (profile, records, bank) = try await checked()
        let id = try #require(ExternalReviewing.entries(records: records, bank: bank).first?.id)
        let a = try ExternalReviewing.read(#"{"reviewer":"A","readings":[{"id":"\#(id)","cynapseRight":true}]}"#, records: records, bank: bank)
        let b = try ExternalReviewing.read(#"{"reviewer":"B","readings":[{"id":"\#(id)","cynapseRight":false}]}"#, records: records, bank: bank)
        let a2 = try ExternalReviewing.read(#"{"reviewer":"A","readings":[{"id":"\#(id)","cynapseRight":false}]}"#, records: records, bank: bank)
        let reviewed = profile.adding(a).adding(b).adding(a2)
        #expect(reviewed.externalReviews?.map(\.reviewer) == ["B", "A"])
        #expect(reviewed.externalReviews?.last?.deviations.count == 1)
        #expect(reviewed.reportLines().filter { $0.heading == "Reviews" }.count == 2)
        // Each line names the AIs that read its answers differently.
        #expect(reviewed.reviewers(differingOn: [id]).map(\.reviewer) == ["B", "A"])
        #expect(reviewed.reviewers(differingOn: ["not-asked"]).isEmpty)
    }

    @Test func aSecondCheckShowsOnlyTheAnswersThatChangedWorstFirst() async throws {
        let bank = try fixtureBank()
        func records(_ behaviour: StubBehaviour) async throws -> [Record] {
            try await Runner(bank: bank, model: StubModel(behaviour, bank: bank), now: fixedNow).run(.quick)
        }
        let honest = try await records(.honest)
        let same = ResultChanges.compare(before: honest, after: honest, bank: bank)
        #expect(same.compared > 0)
        #expect(same.changes.isEmpty)
        // A model that now invents answers: those questions show as worse, first.
        let inventing = ResultChanges.compare(before: honest, after: try await records(.inventor), bank: bank)
        #expect(!inventing.changes.isEmpty)
        #expect(inventing.changes.first?.direction == .worse)
        #expect(inventing.changes.allSatisfy { $0.before != $0.after })
    }

    @Test func theMarkdownReportHoldsEverything() async throws {
        let bank = try fixtureBank()
        func check(_ behaviour: StubBehaviour) async throws -> (Profile, [Record]) {
            let model = StubModel(behaviour, bank: bank)
            let runner = Runner(bank: bank, model: model, now: fixedNow)
            let records = try await runner.run(.quick)
            return (ProfileBuilder.build(records: records, bank: bank, model: model.identity, mode: .quick, baseline: runner.baseline, createdAt: fixedNow), records)
        }
        let (before, beforeRecords) = try await check(.honest)
        let (now, nowRecords) = try await check(.inventor)
        let md = MarkdownReport.make(model: "stub", checks: [.init(profile: now, records: nowRecords, previous: (before, beforeRecords))], bank: bank, now: fixedNow)
        #expect(md.hasPrefix("# Cynapse report: stub"))
        #expect(md.contains("## Quick Character Check"))
        #expect(md.contains("### Changed since the Quick Character Check of"))
        #expect(md.contains("- **Worse: "))
        for line in now.reportLines() { #expect(md.contains(line.text)) }
        for entry in ExternalReviewing.entries(records: nowRecords, bank: bank) { #expect(md.contains("#### \(entry.id) · ")) }
    }

    @Test func aReplyWithNoJSONSaysWhatToDo() async throws {
        let (_, records, bank) = try await checked()
        #expect(throws: ExternalReviewing.ReadError.self) {
            try ExternalReviewing.read("I think it did well.", records: records, bank: bank)
        }
    }
}
