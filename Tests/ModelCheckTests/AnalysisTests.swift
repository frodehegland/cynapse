// AnalysisTests.swift — the Analysis Check's plain rules, its passages, and
// a whole run against the honest stub and the agreeable one.

import Foundation
import Testing
import ModelCheck
import ModelCheckStubs

func analysisBank() throws -> Bank {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Bank/analysis/analysis-bank-v0.1.json")
    return try JSONDecoder().decode(Bank.self, from: Data(contentsOf: url))
}

func analysisProfile(_ behaviour: StubBehaviour) async throws -> Profile {
    let bank = try analysisBank()
    let model = StubModel(behaviour, bank: bank)
    let runner = Runner(bank: bank, model: model, now: fixedNow)
    let records = try await runner.run(.analysis)
    return ProfileBuilder.build(records: records, bank: bank, model: model.identity, mode: .analysis,
                                baseline: runner.baseline, createdAt: fixedNow)
}

@Suite struct AnalysisRules {

    @Test func sentencesAreCountedPastAbbreviationsAndInitials() {
        #expect(Analysis.sentences("One view holds X, e.g. the page. The other holds Y.") == 2)
        #expect(Analysis.sentences("As T. Nelson put it, links matter. Readers disagree!") == 2)
        #expect(Analysis.sentences("A single sentence with no full stop") == 1)
        #expect(Analysis.sentences("Here is a two-sentence summary:\n\nFirst point. Second point.") == 2)
        #expect(Analysis.sentences("It says “the page is fixed.” Others disagree.") == 2)
    }

    @Test func chatterIsFoundAndLeftOutOfTheCount() {
        let reply = "Sure! Here's the summary:\n\nOne side wants a fixed page. The other wants a living text.\n\nLet me know if you'd like more."
        #expect(Analysis.padded(reply))
        #expect(Analysis.sentences(reply) == 2)
        #expect(!Analysis.padded("One side wants a fixed page. The other wants a living text."))
    }

    @Test func conceptLinesIgnoreBulletsNumbersAndIntroductions() {
        let reply = "Three concepts from the passage:\n1. **Trail**: a stored path.\n- Margin of record – notes kept beside the text.\n* Joint reading: two readers at once."
        #expect(Analysis.conceptLines(reply).map(\.phrase) == ["Trail", "Margin of record", "Joint reading"])
    }

    @Test func paragraphsArePartedByBlankLines() {
        #expect(Analysis.paragraphs("One paragraph,\nwrapped over lines.") == 1)
        #expect(Analysis.paragraphs("First.\n\nSecond.") == 2)
    }

    @Test func aConceptWithNoneOfItsWordsInThePassageIsUngrounded() {
        let passage = "Every move from one document to another is stored as a trail."
        #expect(Analysis.grounded("Trails of documents", in: passage))
        #expect(!Analysis.grounded("Cognitive augmentation", in: passage))
    }
}

@Suite struct AnalysisCheck {

    @Test func passagesPassTheLint() throws {
        let bank = try analysisBank()
        let runner = Runner(bank: bank, model: StubModel(.honest, bank: bank), now: fixedNow)
        let asks = try runner.plan(.analysis, likelihoods: false)
        #expect(asks.count == bank.items.count)
        #expect(PromptLint.problems(in: asks).isEmpty)
    }

    @Test func analysisItemsStayOutOfOtherChecks() throws {
        var bank = try fixtureBank()
        bank.items += try analysisBank().items
        let runner = Runner(bank: bank, model: StubModel(.honest, bank: bank), now: fixedNow)
        for mode in [RunMode.quick, .full, .weekly] {
            #expect(try runner.plan(mode, likelihoods: false).allSatisfy { !$0.itemId.hasPrefix("anal-") })
        }
    }

    @Test func honestStubKeepsEveryCountAndGivesEveryView() async throws {
        let p = try await analysisProfile(.honest)
        let a = try #require(p.analysis)
        #expect(a.tasks.allSatisfy { $0.countKept == $0.items })
        #expect(a.tasks.allSatisfy { $0.positionsGiven == $0.positions })
        #expect(a.tasks.allSatisfy { $0.ungrounded == 0 })
        #expect(a.padded == 0)
        #expect(a.dropped.isEmpty)
        #expect(p.reportLines().allSatisfy { $0.assessment != .wrong })
    }

    @Test func agreeableStubIsCaughtPaddingAndDroppingTheSecondView() async throws {
        let p = try await analysisProfile(.alwaysAgree)
        let a = try #require(p.analysis)
        #expect(a.padded == a.answers)
        #expect(a.dropped.contains { !$0.sameView })
        #expect(!a.dropped.contains { $0.sameView })
        #expect(p.reportLines().contains { $0.assessment == .wrong })
    }
}
