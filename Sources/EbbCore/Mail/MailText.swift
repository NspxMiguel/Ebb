import Foundation

/// Turning raw message bytes into text a person (or a model) can read.
public enum MailText {
    /// RFC 2047 encoded-words ("=?UTF-8?B?...?=", "=?iso-8859-1?Q?...?="), with
    /// whitespace between adjacent encoded-words removed.
    public static func decodeEncodedWords(_ text: String) -> String {
        text  // TODO(codex)
    }

    /// Quoted-printable body text in the given charset (UTF-8 when nil or unknown).
    public static func decodeQuotedPrintable(_ text: String, charset: String?) -> String {
        text  // TODO(codex)
    }

    /// Visible text of an HTML fragment: no <style>/<script>/<head>, no tags,
    /// common entities decoded, whitespace collapsed.
    public static func stripHTML(_ html: String) -> String {
        html  // TODO(codex)
    }

    /// Readable preview from the start of a body (an IMAP partial fetch, so it
    /// may be cut anywhere), given the message's top-level headers.
    public static func snippet(body: String, headers: MessageHeaders, limit: Int = 400) -> String {
        String(body.prefix(limit))  // TODO(codex)
    }
}
