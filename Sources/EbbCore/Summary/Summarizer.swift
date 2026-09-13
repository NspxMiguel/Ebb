import Foundation

/// Writes the "what matters" summary of a list of messages.
public protocol Summarizer: Sendable {
    /// Shown under the summary: "On this Mac" or "Groq (openai/gpt-oss-120b)".
    var displayName: String { get }
    func summarize(_ messages: [DigestMessage], account: String, language: Language) async throws -> String
}

/// Groq's OpenAI-compatible API, free tier. Sends sender, subject, date and a
/// short snippet of each message — the user opts in by saving a key.
public struct GroqSummarizer: Summarizer {
    public static let defaultModel = "openai/gpt-oss-120b"
    public let model: String
    let apiKey: String

    public init(apiKey: String, model: String = GroqSummarizer.defaultModel) {
        self.apiKey = apiKey
        self.model = model
    }

    public var displayName: String { "Groq (\(model))" }

    public func summarize(_ messages: [DigestMessage], account: String, language: Language) async throws -> String {
        throw EbbError.summaryFailed("not implemented")  // TODO(lead)
    }
}

public enum SummaryEngine {
    static let groqService = "com.ebb.app.groq"

    public static func groqKey() -> String? { nil }  // TODO(lead)
    public static func setGroqKey(_ key: String) throws {}  // TODO(lead)
    public static func removeGroqKey() {}  // TODO(lead)

    /// Apple's on-device model when Apple Intelligence is on (private, free),
    /// otherwise Groq when a key is saved, otherwise nil.
    public static func preferred() -> Summarizer? { nil }  // TODO(lead)

    /// Localized reason the on-device model cannot be used, nil when it can.
    public static var onDeviceUnavailableReason: String? { nil }  // TODO(lead)
}
