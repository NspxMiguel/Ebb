import Foundation

/// Turning raw message bytes into text a person (or a model) can read.
public enum MailText {
    /// RFC 2047 encoded-words, with whitespace between adjacent words removed.
    public static func decodeEncodedWords(_ text: String) -> String {
        let pattern = #"=\?([^?\s]+)\?([bBqQ])\?([^?]*)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let source = text as NSString
        var result = ""
        var end = 0
        var previousWord = false
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let gap = source.substring(with: NSRange(location: end, length: match.range.location - end))
            if !(previousWord && gap.allSatisfy { " \t\r\n".contains($0) }) { result += gap }
            let charset = source.substring(with: match.range(at: 1))
            let encoding = source.substring(with: match.range(at: 2)).lowercased()
            let payload = source.substring(with: match.range(at: 3))
            let bytes =
                encoding == "b"
                ? Data(base64Encoded: payload) : quotedBytes(payload.replacingOccurrences(of: "_", with: " "))
            if knownCharset(charset), let bytes {
                result += decode(bytes, charset: charset)
            } else {
                result += source.substring(with: match.range)
            }
            previousWord = true
            end = NSMaxRange(match.range)
        }
        return result + source.substring(from: end)
    }

    /// Quoted-printable body text in the given charset (UTF-8 when nil or unknown).
    public static func decodeQuotedPrintable(_ text: String, charset: String?) -> String {
        decode(quotedBytes(text), charset: charset)
    }

    /// Visible text of an HTML fragment.
    public static func stripHTML(_ html: String) -> String {
        var text = replace(html, #"(?is)<(head|style|script)\b[^>]*>.*?(?:</\1\s*>|$)"#, "")
        text = replace(text, #"(?i)<br\b[^>]*>|</(?:p|div|tr|li)\s*>"#, "\n")
        text = replace(text, #"<[^>]*(?:>|$)"#, "")
        let entities = ["nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "#39": "'"]
        if let regex = try? NSRegularExpression(
            pattern: #"&(#x[0-9a-fA-F]+|#[0-9]+|nbsp|amp|lt|gt|quot);"#, options: .caseInsensitive)
        {
            let source = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
                let name = source.substring(with: match.range(at: 1)).lowercased()
                var value = entities[name]
                if name.hasPrefix("#") {
                    let hex = name.hasPrefix("#x")
                    if let number = UInt32(name.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10),
                        let scalar = UnicodeScalar(number)
                    {
                        value = String(scalar)
                    }
                }
                if let value, let range = Range(match.range, in: text) { text.replaceSubrange(range, with: value) }
            }
        }
        text = replace(text.replacingOccurrences(of: "\r\n", with: "\n"), #"[ \t]+"#, " ")
        text = replace(text, #" *\n *"#, "\n")
        return replace(text, #"\n{3,}"#, "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Readable preview from the start of a possibly partial IMAP body.
    public static func snippet(body: String, headers: MessageHeaders, limit: Int = 400) -> String {
        guard limit > 0 else { return "" }
        let parts = readableParts(body, headers: headers, depth: 0)
        let chosen = parts.first { !$0.html } ?? parts.first
        guard let chosen else { return "" }
        let text = replace(chosen.text, #"\s+"#, " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit else { return text }
        let prefix = String(text.prefix(limit))
        let next = text[text.index(text.startIndex, offsetBy: limit)]
        let cut: String
        if next.isWhitespace || prefix.last?.isWhitespace == true {
            cut = prefix
        } else if let space = prefix.lastIndex(of: " ") {
            cut = String(prefix[..<space])
        } else {
            cut = prefix
        }
        return cut.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func readableParts(_ body: String, headers: MessageHeaders, depth: Int) -> [(
        html: Bool, text: String
    )] {
        let contentType = headers.contentType ?? "text/plain"
        let type = contentType.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces).lowercased()
        if type.hasPrefix("multipart/") {
            guard depth < 2, let boundary = parameter("boundary", in: contentType), !boundary.isEmpty else { return [] }
            var result: [(html: Bool, text: String)] = []
            for part in body.components(separatedBy: "--" + boundary).dropFirst() {
                if part.hasPrefix("--") { break }
                let normalized = part.replacingOccurrences(of: "\r\n", with: "\n")
                let raw = normalized.hasPrefix("\n") ? String(normalized.dropFirst()) : normalized
                guard let separator = raw.range(of: "\n\n") else { continue }
                result += readableParts(
                    String(raw[separator.upperBound...]),
                    headers: .parse(String(raw[..<separator.lowerBound])), depth: depth + 1)
            }
            return result
        }
        guard type == "text/plain" || type == "text/html" else { return [] }
        let charset = parameter("charset", in: contentType)
        let encoding = (headers.contentTransferEncoding ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let text: String
        switch encoding {
        case "base64":
            let compact = body.filter { !$0.isWhitespace }
            let complete = String(compact.prefix(compact.count / 4 * 4))
            guard !complete.isEmpty, let bytes = Data(base64Encoded: complete) else { return [] }
            text = decode(bytes, charset: charset)
        case "quoted-printable": text = decodeQuotedPrintable(body, charset: charset)
        default: text = body
        }
        let visible = type == "text/html" ? stripHTML(text) : text
        guard
            visible.unicodeScalars.contains(where: {
                !CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0)
            })
        else { return [] }
        return [(type == "text/html", visible)]
    }

    private static func parameter(_ name: String, in value: String) -> String? {
        let pattern = "(?i)(?:^|;)\\s*" + name + #"\s*=\s*(?:"([^"]*)"|([^;\s]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
        else { return nil }
        let range = match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1)
        return (value as NSString).substring(with: range)
    }

    private static func replace(_ text: String, _ pattern: String, _ replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    private static func knownCharset(_ charset: String) -> Bool {
        ["utf-8", "iso-8859-1", "latin1", "windows-1252", "us-ascii"].contains(charset.lowercased())
    }

    private static func decode(_ bytes: Data, charset: String?) -> String {
        let charset = charset?.lowercased() ?? "utf-8"
        if charset == "windows-1252" {
            let mapping: [UInt32] = [
                0x20AC, 0x81, 0x201A, 0x192, 0x201E, 0x2026, 0x2020, 0x2021,
                0x2C6, 0x2030, 0x160, 0x2039, 0x152, 0x8D, 0x17D, 0x8F,
                0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
                0x2DC, 0x2122, 0x161, 0x203A, 0x153, 0x9D, 0x17E, 0x178,
            ]
            return String(
                String.UnicodeScalarView(
                    bytes.compactMap {
                        UnicodeScalar((0x80...0x9F).contains($0) ? mapping[Int($0) - 0x80] : UInt32($0))
                    }))
        }
        if charset != "iso-8859-1" && charset != "latin1", let text = String(data: bytes, encoding: .utf8) {
            return text
        }
        return String(String.UnicodeScalarView(bytes.compactMap { UnicodeScalar(UInt32($0)) }))
    }

    private static func quotedBytes(_ text: String) -> Data {
        let bytes = Array(text.utf8)
        var output = Data()
        var index = 0
        while index < bytes.count {
            if bytes[index] == 61 {
                if index + 1 < bytes.count, bytes[index + 1] == 10 {
                    index += 2
                    continue
                }
                if index + 2 < bytes.count, bytes[index + 1] == 13, bytes[index + 2] == 10 {
                    index += 3
                    continue
                }
                if index + 2 < bytes.count,
                    bytes[(index + 1)...(index + 2)].allSatisfy({
                        (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
                    }),
                    let byte = UInt8(String(decoding: bytes[(index + 1)...(index + 2)], as: UTF8.self), radix: 16)
                {
                    output.append(byte)
                    index += 3
                    continue
                }
            }
            output.append(bytes[index])
            index += 1
        }
        return output
    }
}
