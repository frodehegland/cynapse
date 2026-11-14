// CloudModel.swift — Claude, ChatGPT and Gemini, called with the person's
// own key over each provider's public API.
//
// Cynapse carries no keys of its own. A key is given by the person (the app
// keeps it in their Keychain) or, for the command-line tool, read from the
// environment. Only the check's own prompts are sent — never anything of the
// person's.

import Foundation
import ModelCheck

public struct CloudModel: CheckedModel {

    public enum Provider: String, Codable, Sendable, CaseIterable {
        case anthropic, openai, gemini

        public var displayName: String {
            switch self {
            case .anthropic: "Claude (Anthropic)"
            case .openai: "ChatGPT (OpenAI)"
            case .gemini: "Gemini (Google)"
            }
        }

        /// A sensible model to start with; the person can name another.
        public var suggestedModel: String {
            switch self {
            case .anthropic: "claude-sonnet-5"
            case .openai: "gpt-5"
            case .gemini: "gemini-2.5-pro"
            }
        }

        /// Where the command-line tool looks for a key.
        public var environmentKey: String {
            switch self {
            case .anthropic: "ANTHROPIC_API_KEY"
            case .openai: "OPENAI_API_KEY"
            case .gemini: "GEMINI_API_KEY"
            }
        }
    }

    public let provider: Provider
    public let model: String
    let key: String
    let session: URLSession

    public init(provider: Provider, model: String, key: String, session: URLSession = .shared) {
        self.provider = provider
        self.model = model
        self.key = key
        self.session = session
    }

    public var identity: ModelIdentity {
        // Cloud models can change without notice: the date is part of who
        // was checked.
        let day = ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone(identifier: "UTC")!, formatOptions: [.withFullDate])
        return ModelIdentity(name: "\(model) (\(day))", provider: "cloud",
                             runtime: .init(name: provider.rawValue, version: "API"),
                             settings: ["temperature": "0", "maxTokens": "800", "checkedOn": day])
    }

    public enum Failure: LocalizedError {
        case http(Int, String)
        case unreadable
        public var errorDescription: String? {
            switch self {
            case .http(let code, let body): "The service answered \(code): \(body.prefix(300))"
            case .unreadable: "The service's answer could not be read."
            }
        }
    }

    public func reply(system: String?, conversation: [Turn]) async throws -> String {
        var request: URLRequest
        var body: [String: Any]
        switch provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = ["model": model, "max_tokens": 800, "temperature": 0,
                    "messages": conversation.map { ["role": $0.role.rawValue, "content": $0.text] }]
            if let system { body["system"] = system }
        case .openai:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            var messages: [[String: String]] = []
            if let system { messages.append(["role": "system", "content": system]) }
            messages += conversation.map { ["role": $0.role.rawValue, "content": $0.text] }
            body = ["model": model, "messages": messages, "temperature": 0, "seed": 7, "max_completion_tokens": 800]
        case .gemini:
            let name = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(name):generateContent")!)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            body = ["contents": conversation.map { ["role": $0.role == .assistant ? "model" : "user", "parts": [["text": $0.text]]] },
                    "generationConfig": ["temperature": 0, "maxOutputTokens": 800, "seed": 7]]
            if let system { body["systemInstruction"] = ["parts": [["text": system]]] }
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Rate limits and brief outages: wait and try again a few times.
        var attempt = 0
        while true {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 429 || code >= 500, attempt < 4 {
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
                continue
            }
            guard code == 200 else { throw Failure.http(code, String(decoding: data, as: UTF8.self)) }
            return try Self.text(from: data, provider: provider)
        }
    }

    static func text(from data: Data, provider: Provider) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.unreadable }
        // Each provider says in its own way that its safety system declined.
        switch provider {
        case .anthropic:
            if json["stop_reason"] as? String == "refusal" { throw ModelRefusal("stop reason: refusal") }
            let blocks = json["content"] as? [[String: Any]] ?? []
            return blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        case .openai:
            let choices = json["choices"] as? [[String: Any]]
            if choices?.first?["finish_reason"] as? String == "content_filter" { throw ModelRefusal("finish reason: content_filter") }
            guard let message = choices?.first?["message"] as? [String: Any] else { throw Failure.unreadable }
            if let refusal = message["refusal"] as? String, !refusal.isEmpty { throw ModelRefusal(refusal) }
            return message["content"] as? String ?? ""
        case .gemini:
            if let feedback = json["promptFeedback"] as? [String: Any], let reason = feedback["blockReason"] as? String {
                throw ModelRefusal("prompt blocked: \(reason)")
            }
            let candidates = json["candidates"] as? [[String: Any]]
            if let reason = candidates?.first?["finishReason"] as? String, ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "RECITATION"].contains(reason) {
                throw ModelRefusal("finish reason: \(reason)")
            }
            let content = candidates?.first?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]] ?? []
            return parts.compactMap { $0["text"] as? String }.joined()
        }
    }
}
