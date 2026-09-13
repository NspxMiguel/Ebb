import XCTest

@testable import EbbCore

final class UIDSetTests: XCTestCase {
    func testCollapsesRanges() {
        XCTAssertEqual(UIDSet.string(from: [8, 1, 2, 3, 5, 7, 3]), "1:3,5,7:8")
        XCTAssertEqual(UIDSet.string(from: []), "")
    }

    func testChunks() {
        XCTAssertEqual(UIDSet.chunks(Array(1...5), size: 2), [[1, 2], [3, 4], [5]])
    }

    func testModifiedUTF7RoundTrip() {
        for name in ["INBOX", "[Gmail]/Lixeira", "Itens Excluídos", "A&B", "日本語"] {
            XCTAssertEqual(ModifiedUTF7.decode(ModifiedUTF7.encode(name)), name)
        }
        XCTAssertEqual(ModifiedUTF7.encode("A&B"), "A&-B")
        XCTAssertEqual(ModifiedUTF7.decode("Itens Exclu&AO0-dos"), "Itens Excluídos")
    }
}
