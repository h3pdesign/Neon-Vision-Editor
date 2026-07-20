import Foundation

private final class NVELockState: @unchecked Sendable {
    nonisolated(unsafe) private let pointer: UnsafeMutableRawPointer
    nonisolated(unsafe) private let destroy: (UnsafeMutableRawPointer) -> Void

    nonisolated init<Value>(_ value: Value, type: Value.Type) {
        pointer = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<Value>.stride,
            alignment: MemoryLayout<Value>.alignment
        )
        pointer.assumingMemoryBound(to: Value.self).initialize(to: value)
        destroy = { pointer in
            pointer.assumingMemoryBound(to: Value.self).deinitialize(count: 1)
            pointer.deallocate()
        }
    }

    deinit {
        destroy(pointer)
    }

    nonisolated func withValue<Value, Result>(
        as type: Value.Type,
        _ body: (inout Value) throws -> Result
    ) rethrows -> Result {
        try body(&pointer.assumingMemoryBound(to: Value.self).pointee)
    }
}

/// A small lock wrapper compatible with the macOS 14 deployment target.
final class NVELock<Value>: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private let state: NVELockState

    nonisolated init(_ value: Value) {
        state = NVELockState(value, type: Value.self)
    }

    nonisolated func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try state.withValue(as: Value.self, body)
    }
}
