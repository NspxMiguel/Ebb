import Foundation
import Network

/// Resumes a continuation at most once — Network.framework callbacks and the
/// timeout race each other, and the loser must be ignored.
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var timer: DispatchWorkItem?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    /// Fails with `EbbError.timeout` unless something resumes first. The timer is
    /// cancelled on resume so thousands of reads don't leave timers queued.
    func armTimeout(_ seconds: TimeInterval, on queue: DispatchQueue) {
        let item = DispatchWorkItem { [weak self] in self?.resume(with: .failure(EbbError.timeout)) }
        lock.lock()
        timer = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        let pendingTimer = timer
        timer = nil
        lock.unlock()
        pendingTimer?.cancel()
        pending?.resume(with: result)
    }
}

/// Byte stream to an IMAP server: TLS (or plain TCP for loopback tests), CRLF
/// lines, and {n} literals folded back into the response as quoted strings.
actor IMAPConnection {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.ebb.imap")
    private let timeout: TimeInterval
    private var buffer = Data()

    init(endpoint: ServerEndpoint, timeout: TimeInterval) {
        let parameters = endpoint.useTLS ? NWParameters(tls: NWProtocolTLS.Options(), tcp: .init()) : .tcp
        let port = NWEndpoint.Port(rawValue: UInt16(clamping: endpoint.port)) ?? 993
        connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: parameters)
        self.timeout = timeout
    }

    func open() async throws {
        let connection = self.connection
        let queue = self.queue
        let timeout = self.timeout
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.resume(with: .success(()))
                case .failed(let error):
                    once.resume(with: .failure(EbbError.connectionFailed(error.localizedDescription)))
                case .waiting(let error):
                    // .waiting retries forever (DNS failure, refused port, bad TLS);
                    // for a background cleanup that is a failure, not a wait.
                    once.resume(with: .failure(EbbError.connectionFailed(error.localizedDescription)))
                    connection.cancel()
                case .cancelled:
                    once.resume(with: .failure(EbbError.connectionFailed("cancelled")))
                default:
                    break
                }
            }
            once.armTimeout(timeout, on: queue)
            connection.start(queue: queue)
        }
    }

    func close() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    func send(_ line: String) async throws {
        let data = Data((line + "\r\n").utf8)
        let connection = self.connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce(continuation)
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        once.resume(with: .failure(EbbError.connectionFailed(error.localizedDescription)))
                    } else {
                        once.resume(with: .success(()))
                    }
                })
        }
    }

    /// One complete response, with literals inlined.
    func readResponse() async throws -> String {
        var response = ""
        while true {
            let line = String(decoding: try await readLine(), as: UTF8.self)
            guard let (prefix, length) = Self.trailingLiteral(line) else {
                response += line
                return response
            }
            let literal = String(decoding: try await readBytes(length), as: UTF8.self)
            response += prefix + IMAPParser.quote(literal)
        }
    }

    /// "... {42}" or "... {42+}" -> ("... ", 42)
    static func trailingLiteral(_ line: String) -> (String, Int)? {
        guard line.hasSuffix("}"), let open = line.lastIndex(of: "{") else { return nil }
        var digits = line[line.index(after: open)..<line.index(before: line.endIndex)]
        if digits.hasSuffix("+") { digits = digits.dropLast() }
        guard !digits.isEmpty, let length = Int(digits) else { return nil }
        return (String(line[..<open]), length)
    }

    private func readLine() async throws -> Data {
        let crlf = Data([13, 10])
        while true {
            if let range = buffer.firstRange(of: crlf) {
                let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer = buffer.subdata(in: range.upperBound..<buffer.endIndex)
                return line
            }
            buffer.append(try await receive())
        }
    }

    private func readBytes(_ count: Int) async throws -> Data {
        while buffer.count < count {
            buffer.append(try await receive())
        }
        let bytes = buffer.subdata(in: buffer.startIndex..<buffer.startIndex + count)
        buffer = buffer.subdata(in: buffer.startIndex + count..<buffer.endIndex)
        return bytes
    }

    private func receive() async throws -> Data {
        let connection = self.connection
        let queue = self.queue
        let timeout = self.timeout
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let once = ResumeOnce(continuation)
            once.armTimeout(timeout, on: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
                data, _, isComplete, error in
                if let error {
                    once.resume(with: .failure(EbbError.connectionFailed(error.localizedDescription)))
                } else if let data, !data.isEmpty {
                    once.resume(with: .success(data))
                } else if isComplete {
                    once.resume(with: .failure(EbbError.connectionFailed("connection closed by the server")))
                } else {
                    once.resume(with: .success(Data()))
                }
            }
        }
    }
}
