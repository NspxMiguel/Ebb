import Foundation

/// RFC 3501 §5.1.3 mailbox name encoding: printable ASCII stays as is, "&" is
/// written "&-", and everything else is UTF-16BE in modified base64 ("," instead
/// of "/", no padding) between "&" and "-". Gmail in Portuguese lists
/// "[Gmail]/Lixeira" plainly but "Itens Excluídos"-style names arrive encoded.
enum ModifiedUTF7 {
    static func decode(_ name: String) -> String {
        var output = ""
        var index = name.startIndex
        while index < name.endIndex {
            let char = name[index]
            guard char == "&" else {
                output.append(char)
                index = name.index(after: index)
                continue
            }
            guard let dash = name[index...].firstIndex(of: "-") else {
                output.append(contentsOf: name[index...])
                break
            }
            let encoded = name[name.index(after: index)..<dash]
            if encoded.isEmpty {
                output.append("&")
            } else {
                var base64 = encoded.replacingOccurrences(of: ",", with: "/")
                while base64.count % 4 != 0 { base64.append("=") }
                if let data = Data(base64Encoded: base64),
                    let text = String(data: data, encoding: .utf16BigEndian)
                {
                    output.append(text)
                } else {
                    output.append(contentsOf: name[index...dash])
                }
            }
            index = name.index(after: dash)
        }
        return output
    }

    static func encode(_ name: String) -> String {
        var output = ""
        var pending: [Character] = []
        func flush() {
            guard !pending.isEmpty else { return }
            let data = String(pending).data(using: .utf16BigEndian) ?? Data()
            let base64 = data.base64EncodedString()
                .replacingOccurrences(of: "/", with: ",")
                .replacingOccurrences(of: "=", with: "")
            output += "&" + base64 + "-"
            pending.removeAll()
        }
        for char in name {
            if let ascii = char.asciiValue, ascii >= 0x20, ascii <= 0x7E {
                flush()
                output += char == "&" ? "&-" : String(char)
            } else {
                pending.append(char)
            }
        }
        flush()
        return output
    }
}
