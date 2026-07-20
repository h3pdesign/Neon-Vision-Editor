import Foundation

/// A small lock wrapper compatible with the macOS 14 deployment target.
final class NVELock<Value>: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var value: Value

    nonisolated init(_ value: Value) {
        self.value = value
    }

    nonisolated func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
