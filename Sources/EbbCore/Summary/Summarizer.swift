import Foundation
import Security

/// Writes the "what matters" summary of a list of messages.
public protocol Summarizer: Sendable {
    /// Shown under the summary: "Apple Intelligence on this Mac" or "Groq (openai/gpt-oss-120b)".
    var displayName: String { get }
    /// True when message content leaves the Mac to produce the summary.
    var sendsMailOffDevice: Bool { get }
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
    public var sendsMailOffDevice: Bool { true }

    public func summarize(_ messages: [DigestMessage], account: String, language: Language) async throws -> String {
        let resolved = language == .system ? L10n.shared.resolved : language
        return try await complete(
            system: SummaryPrompt.instructions(account: account, language: resolved),
            user: SummaryPrompt.messageList(messages, snippetLimit: 400),
            maxTokens: 1500,
            json: false)
    }

    func complete(system: String, user: String, maxTokens: Int, json: Bool) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Groq's edge answers 403 to requests without a User-Agent.
        request.setValue("Ebb/\(EbbVersion.current)", forHTTPHeaderField: "User-Agent")
        var body: [String: Any] = [
            "model": model,
            "temperature": json ? 0 : 0.2,
            "max_completion_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        if json { body["response_format"] = ["type": "json_object"] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw EbbError.summaryFailed(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200 else {
            let message = ((object?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
            throw EbbError.summaryFailed(message)
        }
        guard let choices = object?["choices"] as? [[String: Any]],
            let content = (choices.first?["message"] as? [String: Any])?["content"] as? String,
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw EbbError.summaryFailed("empty response")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum SummaryEngine {
    static let groqService = "com.ebb.app.groq"
    static let groqAccount = "api-key"

    public static func groqKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: groqService,
            kSecAttrAccount as String: groqAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    public static func setGroqKey(_ key: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            removeGroqKey()
            return
        }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: groqService,
            kSecAttrAccount as String: groqAccount,
        ]
        let data = Data(value.utf8)
        var status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Ebb Groq API key"
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public static func removeGroqKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: groqService,
            kSecAttrAccount as String: groqAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Apple's on-device model when Apple Intelligence is on (private, free),
    /// otherwise Groq when a key is saved, otherwise nil.
    public static func preferred() -> Summarizer? {
        if let onDevice = OnDevice.summarizer() { return onDevice }
        if let key = groqKey() { return GroqSummarizer(apiKey: key) }
        return nil
    }

    /// Localized reason the on-device model cannot be used, nil when it can.
    public static var onDeviceUnavailableReason: String? {
        OnDevice.unavailableReason()
    }
}
