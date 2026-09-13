import Foundation

/// IMAP sequence-set helpers for UIDs.
enum UIDSet {
    /// Sorted, deduplicated, ranges collapsed: [1,2,3,5,7,8] -> "1:3,5,7:8".
    static func string(from uids: [UInt32]) -> String {
        let sorted = Array(Set(uids)).sorted()
        guard var start = sorted.first else { return "" }
        var end = start
        var parts: [String] = []
        func flush() { parts.append(start == end ? "\(start)" : "\(start):\(end)") }
        for uid in sorted.dropFirst() {
            if uid == end + 1 {
                end = uid
            } else {
                flush()
                start = uid
                end = uid
            }
        }
        flush()
        return parts.joined(separator: ",")
    }

    /// Splits into chunks so no single command line grows past what servers
    /// accept (Gmail and iCloud cut lines somewhere around 8–10 KB).
    static func chunks(_ uids: [UInt32], size: Int = 500) -> [[UInt32]] {
        let sorted = Array(Set(uids)).sorted()
        return stride(from: 0, to: sorted.count, by: size).map {
            Array(sorted[$0..<min($0 + size, sorted.count)])
        }
    }
}
