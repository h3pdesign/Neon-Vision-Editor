import Foundation
import CryptoKit

/// External document access must cooperate with File Provider, not just write
/// atomically to its local cache. Keep coordination off the UI thread at callers.
nonisolated enum CoordinatedDocumentAccess {
    static func read<T>(at url: URL, _ body: (URL) throws -> T) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<T, Swift.Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            var freshURL = coordinatedURL
            freshURL.removeAllCachedResourceValues()
            result = Result { try body(freshURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    static func write<T>(at url: URL, _ body: (URL) throws -> T) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<T, Swift.Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            var freshURL = coordinatedURL
            freshURL.removeAllCachedResourceValues()
            result = Result { try body(freshURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }

    /// Retain a full local copy even after a provider accepts a write: that is
    /// not proof of server upload. One latest copy per source path, visible in
    /// the app's Documents/Neon Recovery folder, never silently truncated.
    static func recoveryURL(for source: URL, in recoveryDirectory: URL? = nil) throws -> URL? {
        let directory: URL
        if let recoveryDirectory {
            directory = recoveryDirectory
        } else {
#if os(iOS) || os(visionOS)
        guard !source.standardizedFileURL.path.hasPrefix(NSHomeDirectory() + "/") else { return nil }
        directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent("Neon Recovery", isDirectory: true)
#else
            return nil
#endif
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = SHA256.hash(data: Data(source.standardizedFileURL.path.utf8))
            .prefix(12).map { String(format: "%02x", $0) }.joined()
        let displayName = String(decoding: source.lastPathComponent.utf8.prefix(180), as: UTF8.self)
        return directory.appendingPathComponent(key + "-" + displayName)
    }

    static func preserveRecovery(_ data: Data, for source: URL, in directory: URL? = nil) throws {
        if let destination = try recoveryURL(for: source, in: directory) {
            try data.write(to: destination, options: .atomic)
        }
    }

    static func preserveRecovery(from temporary: URL, for source: URL, in directory: URL? = nil) throws {
        guard let destination = try recoveryURL(for: source, in: directory) else { return }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: temporary, to: staging)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: destination)
        }
    }

    /// Content validation, independent of filename. Recognize UTF-16 before
    /// checking control characters so its zero bytes are not mistaken for binary.
    static func isText(_ data: Data, encoding: TextEncodingDescriptor? = nil) -> Bool {
        if data.isEmpty { return true }
        guard let descriptor = encoding ?? FileBackedTextDocument.boundedEncoding(from: data, allowsIncompleteUTF8Sequence: true) else { return false }
        var text: String?
        if descriptor.identifier == .utf8 || descriptor.identifier == .utf8WithBOM {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = descriptor.decode(data)
            // A bounded probe may end between a UTF-16 surrogate pair.
            // Omit only the incomplete suffix, never an interior invalid unit.
            if text == nil, data.count >= 2,
               descriptor.encoding == .utf16LittleEndian || descriptor.encoding == .utf16BigEndian {
                let bytes = Array(data.suffix(2))
                let lastUnit = descriptor.encoding == .utf16LittleEndian
                    ? UInt16(bytes[0]) | UInt16(bytes[1]) << 8
                    : UInt16(bytes[0]) << 8 | UInt16(bytes[1])
                if (0xD800...0xDBFF).contains(lastUnit) {
                    text = descriptor.decode(Data(data.dropLast(2)))
                }
            }
        }
        guard let text else { return false }
        return !text.unicodeScalars.contains { scalar in
            // ANSI escapes, backspace and vertical tabs occur in valid logs
            // and source fixtures. A NUL is the binary signal, not all C0 text.
            scalar.value == 0
        }
    }
}
