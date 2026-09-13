import Foundation

/// Decides whether a message is disposable, from its headers alone.
public enum MessageClassifier {
    /// `.codes` wins over `.bulk`; nil means "everything else".
    public static func kind(of headers: MessageHeaders) -> DisposableKind? {
        let subject = String(MailText.decodeEncodedWords(headers.subject).prefix(200))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let exclusions = [
            "rastreio", "rastreamento", "tracking", "codigo promocional", "cupom", "cupon", "promo code",
            "coupon", "discount code", "code review", "source code", "code scanning", "codeforces",
        ]
        let phrases = [
            "verification code", "security code", "login code", "sign-in code", "sign in code",
            "one-time code", "one time code", "one-time passcode", "passcode", "confirmation code",
            "access code", "authentication code", "2fa code", "otp", "your code", "verify your device",
            "codigo de verificacao", "codigo de seguranca", "codigo de acesso", "codigo de confirmacao",
            "codigo de login", "codigo de uso unico", "codigo de autenticacao", "seu codigo", "e seu codigo",
            "codigo para entrar", "verifique seu dispositivo", "codigo de verificacion", "codigo de seguridad",
            "tu codigo",
        ]
        func matches(_ pattern: String) -> Bool { subject.range(of: pattern, options: .regularExpression) != nil }
        if !exclusions.contains(where: subject.contains) {
            let phrase = phrases.contains { matches("\\b" + NSRegularExpression.escapedPattern(for: $0) + "\\b") }
            let personalized = matches(#"\bis your\b[^\r\n]*\bcode\b"#)
            let signIn = matches(#"\buse [0-9]{4,8} to sign in\b"#)
            let email = matches(#"\b(?:verify|confirm) your email\b"#) && matches(#"\b[0-9]{4,8}\b"#)
            if phrase || personalized || signIn || email { return .codes }
        }
        if [headers.listUnsubscribe, headers.listID].contains(where: {
            !($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            return .bulk
        }
        if ["bulk", "list", "junk"].contains(
            (headers.precedence ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ) {
            return .bulk
        }
        return nil
    }
}
