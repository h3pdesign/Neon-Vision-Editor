import Foundation

private final class NVELockState<Value>: @unchecked Sendable {
    nonisolated(unsafe) var value: Value

    nonisolated init(_ value: Value) {
        self.value = value
    }
}

/// A small lock wrapper compatible with the macOS 14 deployment target.
final class NVELock<Value>: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private let state: NVELockState<Value>

    nonisolated init(_ value: Value) {
        state = NVELockState(value)
    }

    nonisolated func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state.value)
    }
}
