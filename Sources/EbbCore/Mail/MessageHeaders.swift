import Foundation

/// The top-level headers Ebb reads from a message. Values are unfolded and
/// RFC 2047-decoded.
public struct MessageHeaders: Sendable, Hashable {
    /// Display form, e.g. "GitHub <noreply@github.com>".
    public var from: String
    public var subject: String
    public var date: String?
    /// e.g. "multipart/alternative; boundary=\"b1\"".
    public var contentType: String?
    public var contentTransferEncoding: String?
    public var listUnsubscribe: String?
    public var listID: String?
    public var precedence: String?
    public var autoSubmitted: String?

    public init(
        from: String = "", subject: String = "", date: String? = nil, contentType: String? = nil,
        contentTransferEncoding: String? = nil, listUnsubscribe: String? = nil, listID: String? = nil,
        precedence: String? = nil, autoSubmitted: String? = nil
    ) {
        self.from = from
        self.subject = subject
        self.date = date
        self.contentType = contentType
        self.contentTransferEncoding = contentTransferEncoding
        self.listUnsubscribe = listUnsubscribe
        self.listID = listID
        self.precedence = precedence
        self.autoSubmitted = autoSubmitted
    }

    /// Lowercased addr-spec from `from` ("noreply@github.com"); the whole value
    /// lowercased when there are no angle brackets.
    public var fromAddress: String {
        from.lowercased()  // TODO(codex): extract the addr-spec
    }

    /// Parses a raw header block: CRLF or LF line endings, folded continuation
    /// lines, case-insensitive names, first occurrence wins.
    public static func parse(_ raw: String) -> MessageHeaders {
        MessageHeaders()  // TODO(codex)
    }
}
