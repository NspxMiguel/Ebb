import Foundation
import XCTest

@testable import EbbCore

final class MessageClassifierTests: XCTestCase {
    func testCodePhrasesInAllSupportedLanguages() {
        let subjects = [
            "verification code", "security code", "login code", "sign-in code", "sign in code",
            "one-time code", "one time code", "one-time passcode", "passcode", "confirmation code",
            "access code", "authentication code", "2fa code", "OTP", "your code",
            "123456 is your Instagram code", "use 1234 to sign in", "verify your device",
            "verify your email 123456", "12345678 confirm your email", "código de verificação",
            "código de segurança", "código de acesso", "código de confirmação", "código de login",
            "código de uso único", "código de autenticação", "seu código", "1234 é seu código",
            "código para entrar", "verifique seu dispositivo", "código de verificación",
            "código de seguridad", "tu código", "CÓDIGO DE VERIFICAÇÃO",
            "=?UTF-8?B?U2V1IGPDs2RpZ28gZGUgdXNvIMO6bmljbw==?=",
        ]
        for subject in subjects {
            XCTAssertEqual(MessageClassifier.kind(of: MessageHeaders(subject: subject)), .codes, subject)
        }
    }

    func testExcludedSubjectsAndWordBoundaries() {
        let subjects = [
            "rastreio", "rastreamento", "tracking", "código promocional", "cupom", "cupón", "promo code",
            "coupon", "discount code", "code review", "source code", "code scanning", "codeforces",
        ]
        for subject in subjects {
            XCTAssertNil(MessageClassifier.kind(of: MessageHeaders(subject: subject)), subject)
            XCTAssertNil(MessageClassifier.kind(of: MessageHeaders(subject: subject + " your code 1234")), subject)
        }
        for subject in [
            "verify your email", "confirm your email", "verify your email 123", "confirm your email 123456789",
            "adoption", "passcodes", "", "Dinner tonight?",
        ] {
            XCTAssertNil(MessageClassifier.kind(of: MessageHeaders(subject: subject)), subject)
        }
    }

    func testUsesOnlyFirstTwoHundredSubjectCharacters() {
        XCTAssertNil(
            MessageClassifier.kind(of: MessageHeaders(from: "your code", subject: "Hello", autoSubmitted: "OTP")))
        XCTAssertNil(
            MessageClassifier.kind(of: MessageHeaders(subject: String(repeating: "x", count: 200) + " your code")))
    }

    func testBulkHeadersAndCodesPriority() {
        XCTAssertEqual(
            MessageClassifier.kind(of: MessageHeaders(listUnsubscribe: "<mailto:unsubscribe@example.com>")), .bulk)
        XCTAssertEqual(MessageClassifier.kind(of: MessageHeaders(listID: "list.example.com")), .bulk)
        for precedence in ["bulk", " LIST \n", "Junk"] {
            XCTAssertEqual(MessageClassifier.kind(of: MessageHeaders(precedence: precedence)), .bulk)
        }
        XCTAssertNil(
            MessageClassifier.kind(of: MessageHeaders(listUnsubscribe: " \t", listID: "", precedence: "normal")))
        XCTAssertEqual(MessageClassifier.kind(of: MessageHeaders(subject: "your code", listID: "list")), .codes)
        XCTAssertEqual(MessageClassifier.kind(of: MessageHeaders(subject: "promo code", listID: "list")), .bulk)
    }
}
