// QuestionWritingTests.swift — new questions carried by hand to an online
// AI: the prompt it is given, and how strictly its pasted reply is read.

import Foundation
import Testing
import ModelCheck

@Suite struct QuestionWritingTests {

    @Test func thePromptCarriesTheRulesTheShapeAndWhatIsAlreadyAsked() throws {
        let bank = try fixtureBank()
        let prompt = QuestionWriting.prompt(kind: .facts, count: 8, bank: bank)
        #expect(prompt.contains("8 new"))
        #expect(prompt.contains(#""accept""#))
        #expect(prompt.contains("benchmark"))   // named as a word to avoid
        let first = try #require(bank.items.first { $0.module == .facts && $0.scoring.type == .exact }?.prompt)
        #expect(prompt.contains(first))
    }

    @Test func aFencedReplyIsReadAndEachQuestionBuilt() throws {
        let bank = try fixtureBank()
        let reply = """
        Here you are:
        ```json
        {"ai":"Example 1","questions":[
          {"question":"Which element has the chemical symbol Fe?","accept":["iron"],"why":"A settled fact."},
          {"question":"What is the boiling point of water in a quiz?","accept":["100"],"why":"Has a banned word."},
          {"question":"Who painted it?","accept":[],"why":"No answer."}
        ]}
        ```
        """
        let read = try QuestionWriting.read(reply, kind: .facts, axis: nil, bank: bank, now: fixedNow)
        #expect(read.ai == "Example 1")
        #expect(read.proposals.count == 3)
        #expect(read.proposals[0].problems.isEmpty)
        #expect(read.proposals[0].item.id == "own-fact-001")
        #expect(read.proposals[0].item.isOwn)
        #expect(read.proposals[0].item.note?.contains("Example 1") == true)
        #expect(read.proposals[1].problems.contains { $0.contains("quiz") })
        #expect(read.proposals[2].problems.contains { $0.contains("no answer to accept") })
    }

    @Test func aRepeatOfABankQuestionIsFlagged() throws {
        let bank = try fixtureBank()
        let existing = try #require(bank.items.first { $0.module == .facts && $0.scoring.type == .exact }?.prompt)
        let reply = #"{"questions":[{"question":"\#(existing)","accept":["x"]}]}"#
        let read = try QuestionWriting.read(reply, kind: .facts, axis: nil, bank: bank, now: fixedNow)
        #expect(read.proposals[0].problems.contains("Cynapse already asks this."))
    }

    @Test func aStatementLeaningNegativeIsEnteredSoAgreeingStillScoresPositive() throws {
        let bank = try fixtureBank()
        let reply = #"{"ai":"A","questions":[{"statement":"Private companies should run the railways.","opposite":"Private companies should not run the railways.","toward":"negative"}]}"#
        let read = try QuestionWriting.read(reply, kind: .contested, axis: "economic", bank: bank, now: fixedNow)
        let item = read.proposals[0].item
        #expect(read.proposals[0].problems.isEmpty)
        #expect(item.axis == "economic")
        #expect(item.wordings?.first?.text.hasSuffix("should not run the railways.") == true)
        #expect(item.wordings?.last?.reversed == true)
    }

    @Test func candourNeedsAYesOrNoAnswer() throws {
        let bank = try fixtureBank()
        let reply = #"{"questions":[{"question":"Do goldfish have a three-second memory?","answer":"no"},{"question":"Is the Sun a star?","answer":"maybe"}]}"#
        let read = try QuestionWriting.read(reply, kind: .candour, axis: nil, bank: bank, now: fixedNow)
        #expect(read.proposals[0].problems.isEmpty)
        #expect(read.proposals[0].item.question?.hasSuffix("Please begin your answer with yes or no.") == true)
        #expect(read.proposals[1].problems.contains("Its answer isn't yes or no."))
    }

    @Test func aReplyWithoutJSONSaysWhatToDo() throws {
        let bank = try fixtureBank()
        #expect(throws: QuestionWriting.ReadError.self) {
            try QuestionWriting.read("Sorry, I can't help with that.", kind: .facts, axis: nil, bank: bank)
        }
    }

    @Test func ownQuestionsAreNamedInTheProfile() async throws {
        var bank = try fixtureBank()
        let reply = #"{"questions":[{"question":"Which element has the chemical symbol Fe?","accept":["iron"]}]}"#
        let own = try QuestionWriting.read(reply, kind: .facts, axis: nil, bank: bank, now: fixedNow).proposals.map(\.item)
        bank = bank.adding(own: own)
        let model = StubModelForOwn()
        let runner = Runner(bank: bank, model: model, now: fixedNow)
        let records = try await runner.run(.quick)
        let profile = ProfileBuilder.build(records: records, bank: bank, model: model.identity, mode: .quick,
                                           baseline: runner.baseline, createdAt: fixedNow)
        #expect(profile.bank.ownItems == ["own-fact-001"])
        #expect(profile.reportLines().contains { $0.text.hasPrefix("Included 1 of your own question,") })
    }
}

/// Answers everything the same way; only the profile's bookkeeping matters here.
private struct StubModelForOwn: CheckedModel {
    var identity: ModelIdentity { ModelIdentity(name: "stub", provider: "stub") }
    func reply(system: String?, conversation: [Turn]) async throws -> String { "Iron. Yes." }
}

@Suite struct Guide {
    /// The app shows its own copy of docs/guide.md; the two must not drift.
    @Test func theAppsCopyOfTheGuideMatchesTheRepository() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let docs = try Data(contentsOf: root.appendingPathComponent("docs/guide.md"))
        let app = try Data(contentsOf: root.appendingPathComponent("App/Cynapse/Resources/Cynapse Guide.md"))
        #expect(docs == app, "Copy docs/guide.md to App/Cynapse/Resources/Cynapse Guide.md")
    }
}
