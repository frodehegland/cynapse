// Model.swift — what the check needs from a model, whatever runs it.
//
// A local MLX model, Apple's on-device model or a cloud model each conform
// to `CheckedModel` in their own target; the engine never knows which.

import Foundation

public protocol CheckedModel: Sendable {
    var identity: ModelIdentity { get }

    /// The model's reply to the conversation, whose last turn is the user's.
    /// Implementations should use temperature 0 and a fixed seed where the
    /// runtime allows, and say so in `identity.settings`.
    func reply(system: String?, conversation: [Turn]) async throws -> String

    /// The likelihood of each option as the reply, or nil if the runtime
    /// can't say (cloud models, Apple's model): the answer is then generated
    /// and parsed, and marked as such.
    func likelihoods(system: String?, conversation: [Turn], options: [String]) async throws -> [Double]?
}

public extension CheckedModel {
    func likelihoods(system: String?, conversation: [Turn], options: [String]) async throws -> [Double]? { nil }

    func reply(system: String?, conversation: [Turn], onChunk: @escaping @Sendable (String) -> Void) async throws -> String {
        let text = try await reply(system: system, conversation: conversation)
        onChunk(text)
        return text
    }
}

/// A model that can show its answer as it writes it.
public protocol StreamingCheckedModel: CheckedModel {
    func reply(system: String?, conversation: [Turn], onChunk: @escaping @Sendable (String) -> Void) async throws -> String
}

/// Everything known about the model being checked, recorded in the profile.
public struct ModelIdentity: Codable, Sendable, Hashable {
    public var name: String
    /// "local", "apple", "cloud" or "stub".
    public var provider: String
    /// SHA-256 over the model's files (see `ModelFingerprint`); nil when
    /// there is no file, as for cloud models.
    public var sha256: String?
    public var fileSize: Int64?
    public var quantisation: String?
    public var runtime: Runtime?
    /// Temperature, seed and so on, as actually used.
    public var settings: [String: String]

    public struct Runtime: Codable, Sendable, Hashable {
        public var name: String
        public var version: String
        public init(name: String, version: String) { self.name = name; self.version = version }
    }

    public init(name: String, provider: String, sha256: String? = nil, fileSize: Int64? = nil,
                quantisation: String? = nil, runtime: Runtime? = nil, settings: [String: String] = [:]) {
        self.name = name
        self.provider = provider
        self.sha256 = sha256
        self.fileSize = fileSize
        self.quantisation = quantisation
        self.runtime = runtime
        self.settings = settings
    }
}
