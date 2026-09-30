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
    enum Identifier: Hashable, CaseIterable, Sendable, Codable, RawRepresentable {
        case utf8
        case utf8WithBOM
        case utf16LittleEndian
        case utf16LittleEndianWithBOM
        case utf16BigEndian
        case utf16BigEndianWithBOM
        case utf32LittleEndian
        case utf32LittleEndianWithBOM
        case utf32BigEndian
        case utf32BigEndianWithBOM
        case isoLatin1
        case isoLatin5
        case windowsCP1252
        case windowsCP1251
        case macOSRoman
        case ascii
        case foundation(UInt)

        nonisolated static let allCases: [Self] = [.utf8, .utf8WithBOM, .utf16LittleEndian, .utf16LittleEndianWithBOM, .utf16BigEndian, .utf16BigEndianWithBOM, .utf32LittleEndian, .utf32LittleEndianWithBOM, .utf32BigEndian, .utf32BigEndianWithBOM, .isoLatin1, .isoLatin5, .windowsCP1252, .windowsCP1251, .macOSRoman, .ascii]

        nonisolated var rawValue: String {
            switch self {
            case .utf8: return "utf8"
            case .utf8WithBOM: return "utf8WithBOM"
            case .utf16LittleEndian: return "utf16LittleEndian"
            case .utf16LittleEndianWithBOM: return "utf16LittleEndianWithBOM"
            case .utf16BigEndian: return "utf16BigEndian"
            case .utf16BigEndianWithBOM: return "utf16BigEndianWithBOM"
            case .utf32LittleEndian: return "utf32LittleEndian"
            case .utf32LittleEndianWithBOM: return "utf32LittleEndianWithBOM"
            case .utf32BigEndian: return "utf32BigEndian"
            case .utf32BigEndianWithBOM: return "utf32BigEndianWithBOM"
            case .isoLatin1: return "isoLatin1"
            case .isoLatin5: return "isoLatin5"
            case .windowsCP1252: return "windowsCP1252"
            case .windowsCP1251: return "windowsCP1251"
            case .macOSRoman: return "macOSRoman"
            case .ascii: return "ascii"
            case .foundation(let raw): return "foundation:\(raw)"
            }
        }

        nonisolated init?(rawValue: String) {
            if let known = Self.allCases.first(where: { $0.rawValue == rawValue }) {
                self = known
            } else if rawValue.hasPrefix("foundation:"),
                      let raw = UInt(rawValue.dropFirst("foundation:".count)),
                      String.availableStringEncodings.contains(String.Encoding(rawValue: raw)) {
                self = .foundation(raw)
            } else {
                return nil
            }
        }

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let value = Self(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported text encoding")
            }
            self = value
        }

        nonisolated func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
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
        case .utf32LittleEndian: return "UTF-32 Little Endian"
        case .utf32LittleEndianWithBOM: return "UTF-32 Little Endian with BOM"
        case .utf32BigEndian: return "UTF-32 Big Endian"
        case .utf32BigEndianWithBOM: return "UTF-32 Big Endian with BOM"
        case .isoLatin1: return "ISO Latin 1"
        case .isoLatin5: return "ISO Latin 5"
        case .windowsCP1252: return "Windows CP 1252"
        case .windowsCP1251: return "Windows CP 1251"
        case .macOSRoman: return "Mac OS Roman"
        case .ascii: return "US-ASCII"
        case .foundation: return String.localizedName(of: encoding)
        }
    }

    nonisolated var encoding: String.Encoding {
        switch identifier {
        case .utf8, .utf8WithBOM: return .utf8
        case .utf16LittleEndian, .utf16LittleEndianWithBOM: return .utf16LittleEndian
        case .utf16BigEndian, .utf16BigEndianWithBOM: return .utf16BigEndian
        case .utf32LittleEndian, .utf32LittleEndianWithBOM: return .utf32LittleEndian
        case .utf32BigEndian, .utf32BigEndianWithBOM: return .utf32BigEndian
        case .isoLatin1: return .isoLatin1
        case .isoLatin5: return Self.isoLatin5Encoding
        case .windowsCP1252: return .windowsCP1252
        case .windowsCP1251: return .windowsCP1251
        case .macOSRoman: return .macOSRoman
        case .ascii: return .ascii
        case .foundation(let raw): return String.Encoding(rawValue: raw)
        }
    }

    nonisolated var encodingRawValue: UInt { encoding.rawValue }

    nonisolated var supportsBoundedStorage: Bool {
        switch identifier {
        case .utf8, .utf8WithBOM, .utf16LittleEndian, .utf16LittleEndianWithBOM,
             .utf16BigEndian, .utf16BigEndianWithBOM, .isoLatin1, .isoLatin5,
             .windowsCP1252, .windowsCP1251, .macOSRoman, .ascii: return true
        default: return false
        }
    }

    nonisolated private var byteOrderMark: Data? {
        switch identifier {
        case .utf8WithBOM: return Data([0xEF, 0xBB, 0xBF])
        case .utf16LittleEndianWithBOM: return Data([0xFF, 0xFE])
        case .utf16BigEndianWithBOM: return Data([0xFE, 0xFF])
        case .utf32LittleEndianWithBOM: return Data([0xFF, 0xFE, 0x00, 0x00])
        case .utf32BigEndianWithBOM: return Data([0x00, 0x00, 0xFE, 0xFF])
        default: return nil
        }
    }

    nonisolated static let utf8 = Self(identifier: .utf8)
    nonisolated static let all: [Self] = {
        let known = Identifier.allCases.map(Self.init(identifier:))
        let knownEncodings = Set(known.map(\.encodingRawValue))
        let additional = String.availableStringEncodings
            .filter { !knownEncodings.contains($0.rawValue) }
            .map { Self(identifier: .foundation($0.rawValue)) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return known + additional
    }()

    nonisolated static func descriptor(forRawValue rawValue: UInt) -> Self {
        let encoding = String.Encoding(rawValue: rawValue)
        switch encoding {
        case .utf16LittleEndian: return Self(identifier: .utf16LittleEndian)
        case .utf16BigEndian: return Self(identifier: .utf16BigEndian)
        case .utf32LittleEndian: return Self(identifier: .utf32LittleEndian)
        case .utf32BigEndian: return Self(identifier: .utf32BigEndian)
        case .isoLatin1: return Self(identifier: .isoLatin1)
        case Self.isoLatin5Encoding: return Self(identifier: .isoLatin5)
        case .windowsCP1252: return Self(identifier: .windowsCP1252)
        case .windowsCP1251: return Self(identifier: .windowsCP1251)
        case .macOSRoman: return Self(identifier: .macOSRoman)
        case .ascii: return Self(identifier: .ascii)
        case .utf8: return .utf8
        default:
            return String.availableStringEncodings.contains(encoding)
                ? Self(identifier: .foundation(rawValue)) : .utf8
        }
    }

    nonisolated static func detected(in data: Data) -> Self? {
        if data.starts(with: [0xFF, 0xFE, 0x00, 0x00]) { return Self(identifier: .utf32LittleEndianWithBOM) }
        if data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) { return Self(identifier: .utf32BigEndianWithBOM) }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return Self(identifier: .utf8WithBOM) }
        if data.starts(with: [0xFF, 0xFE]) { return Self(identifier: .utf16LittleEndianWithBOM) }
        if data.starts(with: [0xFE, 0xFF]) { return Self(identifier: .utf16BigEndianWithBOM) }

        if String(data: data, encoding: .utf8) != nil { return .utf8 }
        // Unrestricted detection can interpret short Cyrillic text as CJK or
        // BOM-less UTF-16. Keep the established legacy candidates and only
        // suggest Shift-JIS when its strict decode contains full-width Japanese
        // characters (not the half-width kana produced by Cyrillic bytes).
        var candidates: [String.Encoding] = [.windowsCP1251, .windowsCP1252]
        if let japanese = String(data: data, encoding: .shiftJIS),
           japanese.unicodeScalars.contains(where: {
               (0x3000...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) || (0xFF01...0xFF60).contains($0.value)
           }) {
            candidates.insert(.shiftJIS, at: 0)
        }
        if !candidates.contains(.shiftJIS), let cyrillic = String(data: data, encoding: .windowsCP1251) {
            var run = 0
            for scalar in cyrillic.unicodeScalars {
                run = (0x0400...0x04FF).contains(scalar.value) ? run + 1 : 0
                // Foundation favors CP1252 for all-uppercase Cyrillic samples.
                // Preserve the established encoding for an actual Cyrillic run.
                if run >= 3 { return Self(identifier: .windowsCP1251) }
            }
        }
        var lossy = ObjCBool(false)
        let raw = NSString.stringEncoding(for: data, encodingOptions: [
            .suggestedEncodingsKey: candidates.map(\.rawValue),
            .useOnlySuggestedEncodingsKey: true,
            .allowLossyKey: false
        ], convertedString: nil, usedLossyConversion: &lossy)
        if raw != 0, !lossy.boolValue {
            let descriptor = Self.descriptor(forRawValue: raw)
            if descriptor.decode(data) != nil { return descriptor }
        }
        let fallbackCandidates = candidates + [.isoLatin1, Self.isoLatin5Encoding, .macOSRoman]
        return fallbackCandidates.map { Self.descriptor(forRawValue: $0.rawValue) }.first { $0.decode(data) != nil }
    }

    nonisolated func decode(_ data: Data) -> String? {
        if let byteOrderMark {
            if identifier == .utf8WithBOM {
                return String(data: data.dropFirst(3), encoding: .utf8)
            }
            if identifier == .utf32LittleEndianWithBOM || identifier == .utf32BigEndianWithBOM {
                let payload = data.starts(with: byteOrderMark) ? Data(data.dropFirst(4)) : data
                return String(data: payload, encoding: encoding)
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
