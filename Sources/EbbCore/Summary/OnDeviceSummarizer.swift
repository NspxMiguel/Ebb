import Foundation

#if canImport(FoundationModels)
    import FoundationModels

    /// Apple's on-device model (macOS 26 with Apple Intelligence). Nothing leaves
    /// the Mac. Its context is a few thousand tokens, so it sees fewer messages
    /// with shorter snippets, and retries with half as many if they still overflow.
    @available(macOS 26.0, *)
    public struct OnDeviceSummarizer: Summarizer {
        public init() {}

        public static var isAvailable: Bool {
            if case .available = SystemLanguageModel.default.availability { return true }
            return false
        }

        public var displayName: String { L10n.shared("summary.on_device") }
        public var sendsMailOffDevice: Bool { false }

        public func summarize(_ messages: [DigestMessage], account: String, language: Language) async throws
            -> String
        {
            let resolved = language == .system ? L10n.shared.resolved : language
            var count = min(messages.count, 25)
            while true {
                let session = LanguageModelSession(
                    instructions: SummaryPrompt.instructions(account: account, language: resolved))
                do {
                    let prompt = SummaryPrompt.messageList(Array(messages.prefix(count)), snippetLimit: 160)
                    return try await session.respond(to: prompt).content
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                    guard count > 4 else { throw EbbError.summaryFailed("context window exceeded") }
                    count /= 2
                } catch {
                    throw EbbError.summaryFailed(error.localizedDescription)
                }
            }
        }
    }
#endif

enum OnDevice {
    static func summarizer() -> Summarizer? {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *), OnDeviceSummarizer.isAvailable {
                return OnDeviceSummarizer()
            }
        #endif
        return nil
    }

    static func unavailableReason() -> String? {
        let t = L10n.shared
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                switch SystemLanguageModel.default.availability {
                case .available:
                    return nil
                case .unavailable(.appleIntelligenceNotEnabled):
                    return t("summary.reason.not_enabled")
                case .unavailable(.deviceNotEligible):
                    return t("summary.reason.not_eligible")
                case .unavailable(.modelNotReady):
                    return t("summary.reason.not_ready")
                case .unavailable:
                    return t("summary.reason.not_enabled")
                }
            }
        #endif
        return t("summary.reason.old_macos")
    }
}
