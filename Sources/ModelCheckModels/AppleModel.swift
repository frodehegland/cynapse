// AppleModel.swift — the model built into macOS (Apple Intelligence),
// through the FoundationModels framework.
//
// It is the same for everyone on the same version of macOS, so its profile
// is keyed by that version. Text only: no likelihoods, so choices are
// generated and parsed, and marked as such.

import Foundation
import ModelCheck

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, iOS 26.0, visionOS 26.0, *)
public struct AppleModel: StreamingCheckedModel {

    public init() {}

    /// Whether the model can be used on this Mac now, and if not, why.
    public static var availability: (available: Bool, reason: String?) {
        switch SystemLanguageModel.default.availability {
        case .available: return (true, nil)
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return (false, "This Mac can't run Apple Intelligence.")
            case .appleIntelligenceNotEnabled: return (false, "Apple Intelligence is turned off in System Settings.")
            case .modelNotReady: return (false, "Apple Intelligence is still getting ready.")
            @unknown default: return (false, "Apple Intelligence isn't available.")
            }
        }
    }

    static func isRefusal(_ error: Error) -> Bool {
        if error is ModelRefusal { return true }
        let text = (String(describing: error) + " " + error.localizedDescription).lowercased()
        return text.contains("guardrail") || text.contains("refusal") || text.contains("unsafe")
    }

    public var identity: ModelIdentity {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return ModelIdentity(name: "Apple Intelligence (\(os))", provider: "apple",
                             runtime: .init(name: "FoundationModels", version: os),
                             settings: ["sampling": "greedy", "maxTokens": "800"])
    }

    public func reply(system: String?, conversation: [Turn]) async throws -> String {
        try await reply(system: system, conversation: conversation) { _ in }
    }

    public func reply(system: String?, conversation: [Turn], onChunk: @escaping @Sendable (String) -> Void) async throws -> String {
        // Earlier turns go into the instructions as a transcript, since a
        // fresh session can't be handed a history of its own.
        var instructions = system ?? ""
        let prior = conversation.dropLast()
        if !prior.isEmpty {
            instructions += "\n\nThe conversation so far:\n" + prior.map { "\($0.role == .user ? "User" : "Assistant"): \($0.text)" }.joined(separator: "\n")
        }
        let session = LanguageModelSession(instructions: instructions.isEmpty ? nil : instructions)
        let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 800)
        var text = ""
        do {
            for try await snapshot in session.streamResponse(to: conversation.last?.text ?? "", options: options) {
                let full = snapshot.content
                if full.count > text.count { onChunk(String(full.dropFirst(text.count))) }
                text = full
            }
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal:
                throw ModelRefusal(error.localizedDescription)
            default:
                throw error
            }
        } catch {
            // The guardrails don't always arrive as a GenerationError (seen
            // on macOS 27: the stream ended with a bridged error). Whatever
            // the type, a guardrail or a refusal is the model declining, and
            // is recorded as that; it must never stop the check.
            if Self.isRefusal(error) { throw ModelRefusal(error.localizedDescription) }
            throw error
        }
        return text
    }
}
#endif
