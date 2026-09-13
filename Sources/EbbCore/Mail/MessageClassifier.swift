import Foundation

/// Decides whether a message is disposable, from its headers alone.
public enum MessageClassifier {
    /// `.codes` wins over `.bulk`; nil means "everything else".
    public static func kind(of headers: MessageHeaders) -> DisposableKind? {
        nil  // TODO(codex)
    }
}
