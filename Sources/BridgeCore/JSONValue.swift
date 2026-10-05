import Foundation

public enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n.isFinite ? n : 0)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var doubleValue: Double? { if case .number(let n) = self { return n }; return nil }
    public var intValue: Int? { doubleValue.flatMap { Int(exactly: $0.rounded(.towardZero)) } }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }

    public init(any: Any) {
        switch any {
        case let s as String: self = .string(s)
        case let n as NSNumber:
            self = String(cString: n.objCType) == "c" ? .bool(n.boolValue) : .number(n.doubleValue)
        case let a as [Any]: self = .array(a.map(JSONValue.init(any:)))
        case let o as [String: Any]: self = .object(o.mapValues(JSONValue.init(any:)))
        default: self = .null
        }
    }
}

public enum JSON {
    // Fractional seconds so "newer than" between a note and its collection works
    // within one second. Whole-second dates keep the plain format so older files
    // round-trip byte for byte.
    static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    static let whole = Date.ISO8601FormatStyle()
    static let dateEncoding = JSONEncoder.DateEncodingStrategy.custom { date, encoder in
        var c = encoder.singleValueContainer()
        let ms = (date.timeIntervalSince1970 * 1000).rounded()
        try c.encode(date.formatted(ms.truncatingRemainder(dividingBy: 1000) == 0 ? whole : fractional))
    }
    static let dateDecoding = JSONDecoder.DateDecodingStrategy.custom { decoder in
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        if let d = try? fractional.parse(s) { return d }
        if let d = try? whole.parse(s) { return d }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "not an ISO 8601 date: \(s)")
    }
    nonisolated(unsafe) public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = dateEncoding
        return e
    }()
    nonisolated(unsafe) public static let compact: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = dateEncoding
        return e
    }()
    nonisolated(unsafe) public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = dateDecoding
        return d
    }()

    public static func string<T: Encodable>(_ value: T, pretty: Bool = true) -> String {
        let data = (try? (pretty ? encoder : compact).encode(value)) ?? Data("null".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
