import Foundation

/// A parsed piece of an IMAP response: atoms (including NIL and numbers),
/// quoted strings (literals are inlined as strings by the connection), and
/// parenthesized lists.
indirect enum IMAPValue: Equatable {
    case atom(String)
    case string(String)
    case list([IMAPValue])

    /// Atom or string content, for places where the grammar allows either.
    var text: String? {
        switch self {
        case .atom(let value), .string(let value): return value
        case .list: return nil
        }
    }

    var items: [IMAPValue]? {
        if case .list(let values) = self { return values }
        return nil
    }
}

enum IMAPParser {
    /// Tokenizes a response (or the part after the untagged keyword) into values.
    static func values(_ input: Substring) -> [IMAPValue] {
        var index = input.startIndex
        return parseSequence(input, &index, closing: false)
    }

    private static func parseSequence(_ s: Substring, _ i: inout Substring.Index, closing: Bool) -> [IMAPValue] {
        var result: [IMAPValue] = []
        while i < s.endIndex {
            let c = s[i]
            if c == " " {
                i = s.index(after: i)
            } else if c == "(" {
                i = s.index(after: i)
                result.append(.list(parseSequence(s, &i, closing: true)))
            } else if c == ")" {
                i = s.index(after: i)
                if closing { return result }
            } else if c == "\"" {
                result.append(.string(parseQuoted(s, &i)))
            } else {
                result.append(.atom(parseAtom(s, &i)))
            }
        }
        return result
    }

    private static func parseQuoted(_ s: Substring, _ i: inout Substring.Index) -> String {
        var out = ""
        i = s.index(after: i)  // opening quote
        while i < s.endIndex {
            let c = s[i]
            if c == "\\" {
                let next = s.index(after: i)
                if next < s.endIndex {
                    out.append(s[next])
                    i = s.index(after: next)
                    continue
                }
            } else if c == "\"" {
                i = s.index(after: i)
                return out
            }
            out.append(c)
            i = s.index(after: i)
        }
        return out
    }

    /// Atoms run until a space, a parenthesis or a quote. Square brackets stay
    /// inside the atom so response codes like [READ-WRITE] survive intact,
    /// except that a "[" opens a section whose spaces belong to the atom.
    private static func parseAtom(_ s: Substring, _ i: inout Substring.Index) -> String {
        var out = ""
        var bracketDepth = 0
        while i < s.endIndex {
            let c = s[i]
            if c == "[" { bracketDepth += 1 }
            if c == "]" { bracketDepth = max(0, bracketDepth - 1) }
            if bracketDepth == 0, c == " " || c == "(" || c == ")" || c == "\"" { break }
            out.append(c)
            i = s.index(after: i)
        }
        return out
    }

    static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: - Specific responses

    /// "* LIST (\HasNoChildren \Trash) "/" "[Gmail]/Trash"" -> flags and raw name.
    static func listEntry(_ line: String) -> (flags: [String], name: String)? {
        guard let rest = untaggedPayload(line, keyword: "LIST") else { return nil }
        let parts = values(rest)
        guard parts.count >= 3, let flags = parts[0].items, let name = parts[2].text else { return nil }
        return (flags.compactMap(\.text), name)
    }

    /// "* SEARCH 1 2 3" -> [1, 2, 3]
    static func searchResults(_ line: String) -> [UInt32]? {
        guard let rest = untaggedPayload(line, keyword: "SEARCH") else { return nil }
        return values(rest).compactMap { $0.text.flatMap(UInt32.init) }
    }

    /// "* 3 EXISTS" -> 3
    static func exists(_ line: String) -> Int? {
        let parts = line.split(separator: " ")
        guard parts.count >= 3, parts[0] == "*", parts[2].uppercased() == "EXISTS" else { return nil }
        return Int(parts[1])
    }

    /// Capabilities from "* CAPABILITY ..." or a "[CAPABILITY ...]" response code.
    static func capabilities(_ line: String) -> Set<String>? {
        if let rest = untaggedPayload(line, keyword: "CAPABILITY") {
            return Set(rest.split(separator: " ").map { $0.uppercased() })
        }
        guard let open = line.range(of: "[CAPABILITY ", options: .caseInsensitive),
            let close = line[open.upperBound...].firstIndex(of: "]")
        else { return nil }
        return Set(line[open.upperBound..<close].split(separator: " ").map { $0.uppercased() })
    }

    /// "* 12 FETCH (UID 345 INTERNALDATE "..." FLAGS (\Seen))" -> attribute map.
    static func fetchAttributes(_ line: String) -> [String: IMAPValue]? {
        let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count == 4, parts[0] == "*", parts[2].uppercased() == "FETCH" else { return nil }
        guard let list = values(parts[3]).first?.items else { return nil }
        var attributes: [String: IMAPValue] = [:]
        var index = 0
        while index + 1 < list.count {
            if let key = list[index].text?.uppercased() {
                attributes[key] = list[index + 1]
            }
            index += 2
        }
        return attributes
    }

    /// "* LIST ..." -> the substring after the keyword, case-insensitive.
    static func untaggedPayload(_ line: String, keyword: String) -> Substring? {
        let prefix = "* \(keyword)"
        guard line.count >= prefix.count,
            line.prefix(prefix.count).caseInsensitiveCompare(prefix) == .orderedSame
        else { return nil }
        let rest = line.dropFirst(prefix.count)
        if rest.isEmpty { return rest }
        guard rest.first == " " else { return nil }
        return rest.dropFirst()
    }
}
