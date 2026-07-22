import Foundation
import CoreFoundation

/// The concrete byte representation used for an open text document.
///
/// `String.Encoding` alone cannot distinguish UTF-8 with a byte-order mark from
/// plain UTF-8, so the descriptor keeps that document-level choice explicit.
struct TextEncodingDescriptor: Identifiable, Hashable, Sendable {
    nonisolated private static let isoLatin5Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0209))
    )
    enum Identifier: String, CaseIterable, Sendable {
        case utf8
        case utf8WithBOM
        case utf16LittleEndian
        case utf16LittleEndianWithBOM
        case utf16BigEndian
        case utf16BigEndianWithBOM
        case isoLatin1
        case isoLatin5
        case windowsCP1252
        case windowsCP1251
        case macOSRoman
        case ascii
    }

    let identifier: Identifier

    nonisolated var id: String { identifier.rawValue }

    nonisolated var displayName: String {
        switch identifier {
        case .utf8: return "UTF-8"
        case .utf8WithBOM: return "UTF-8 with BOM"
        case .utf16LittleEndian: return "UTF-16 Little Endian"
        case .utf16LittleEndianWithBOM: return "UTF-16 Little Endian with BOM"
        case .utf16BigEndian: return "UTF-16 Big Endian"
        case .utf16BigEndianWithBOM: return "UTF-16 Big Endian with BOM"
        case .isoLatin1: return "ISO Latin 1"
        case .isoLatin5: return "ISO Latin 5"
        case .windowsCP1252: return "Windows CP 1252"
        case .windowsCP1251: return "Windows CP 1251"
        case .macOSRoman: return "Mac OS Roman"
        case .ascii: return "US-ASCII"
        }
    }

    nonisolated var encoding: String.Encoding {
        switch identifier {
        case .utf8, .utf8WithBOM: return .utf8
        case .utf16LittleEndian, .utf16LittleEndianWithBOM: return .utf16LittleEndian
        case .utf16BigEndian, .utf16BigEndianWithBOM: return .utf16BigEndian
        case .isoLatin1: return .isoLatin1
        case .isoLatin5: return Self.isoLatin5Encoding
        case .windowsCP1252: return .windowsCP1252
        case .windowsCP1251: return .windowsCP1251
        case .macOSRoman: return .macOSRoman
        case .ascii: return .ascii
        }
    }

    nonisolated var encodingRawValue: UInt { encoding.rawValue }

    nonisolated private var byteOrderMark: Data? {
        switch identifier {
        case .utf8WithBOM: return Data([0xEF, 0xBB, 0xBF])
        case .utf16LittleEndianWithBOM: return Data([0xFF, 0xFE])
        case .utf16BigEndianWithBOM: return Data([0xFE, 0xFF])
        default: return nil
        }
    }

    nonisolated static let utf8 = Self(identifier: .utf8)
    nonisolated static let all: [Self] = Identifier.allCases.map(Self.init(identifier:))

    nonisolated static func descriptor(forRawValue rawValue: UInt) -> Self {
        let encoding = String.Encoding(rawValue: rawValue)
        switch encoding {
        case .utf16LittleEndian: return Self(identifier: .utf16LittleEndian)
        case .utf16BigEndian: return Self(identifier: .utf16BigEndian)
        case .isoLatin1: return Self(identifier: .isoLatin1)
        case Self.isoLatin5Encoding: return Self(identifier: .isoLatin5)
        case .windowsCP1252: return Self(identifier: .windowsCP1252)
        case .windowsCP1251: return Self(identifier: .windowsCP1251)
        case .macOSRoman: return Self(identifier: .macOSRoman)
        case .ascii: return Self(identifier: .ascii)
        default: return .utf8
        }
    }

    nonisolated static func detected(in data: Data) -> Self? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return Self(identifier: .utf8WithBOM) }
        if data.starts(with: [0xFF, 0xFE]) { return Self(identifier: .utf16LittleEndianWithBOM) }
        if data.starts(with: [0xFE, 0xFF]) { return Self(identifier: .utf16BigEndianWithBOM) }

        for descriptor in all where descriptor.byteOrderMark == nil {
            if String(data: data, encoding: descriptor.encoding) != nil {
                return descriptor
            }
        }
        return nil
    }

    nonisolated func decode(_ data: Data) -> String? {
        if byteOrderMark != nil {
            if identifier == .utf8WithBOM {
                return String(data: data.dropFirst(3), encoding: .utf8)
            }
            return String(data: data, encoding: .utf16)
        }
        return String(data: data, encoding: encoding)
    }

    nonisolated func encodedData(for text: String) -> Data? {
        guard var data = text.data(using: encoding, allowLossyConversion: false) else { return nil }
        if let byteOrderMark {
            data.insert(contentsOf: byteOrderMark, at: data.startIndex)
        }
        return data
    }
}
