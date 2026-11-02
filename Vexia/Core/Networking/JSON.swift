import Foundation

/// Dynamic JSON value with tolerant accessors.
/// Numbers may arrive as strings and keys may vary, so accessors coerce instead of failing.
nonisolated enum JSON: Hashable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSON]), object([String: JSON])

    nonisolated init(any: Any?) {
        switch any {
        case nil, is NSNull: self = .null
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) } else { self = .number(n.doubleValue) }
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map { JSON(any: $0) })
        case let o as [String: Any]: self = .object(o.mapValues { JSON(any: $0) })
        default: self = .null
        }
    }

    nonisolated static func parse(_ data: Data) throws -> JSON {
        if data.isEmpty { return .null }
        return JSON(any: try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    nonisolated subscript(key: String) -> JSON {
        if case .object(let o) = self { return o[key] ?? .null }
        return .null
    }

    /// First non-null value among several candidate keys (camelCase / snake_case fallbacks).
    nonisolated func first(_ keys: String...) -> JSON {
        for k in keys { let v = self[k]; if v != .null { return v } }
        return .null
    }

    nonisolated var isNull: Bool { self == .null }

    nonisolated var string: String? {
        switch self {
        case .string(let s): s
        case .number(let n): n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .bool(let b): String(b)
        default: nil
        }
    }
    nonisolated var stringValue: String { string ?? "" }

    nonisolated var double: Double? {
        switch self {
        case .number(let n): n
        case .string(let s): Double(s.trimmingCharacters(in: .whitespaces))
        case .bool(let b): b ? 1 : 0
        default: nil
        }
    }
    nonisolated var doubleValue: Double { double ?? 0 }
    nonisolated var int: Int? { double.map { Int($0) } }
    nonisolated var intValue: Int { int ?? 0 }

    nonisolated var bool: Bool? {
        switch self {
        case .bool(let b): b
        case .number(let n): n != 0
        case .string(let s): ["true", "1", "yes"].contains(s.lowercased())
        default: nil
        }
    }
    nonisolated func bool(default d: Bool) -> Bool { bool ?? d }

    nonisolated var array: [JSON] {
        switch self {
        case .array(let a): a
        // Some endpoints send lists as JSON-encoded strings (e.g. Transaction.tags, Snapshot.itemsDetail)
        case .string(let s): (try? JSON.parse(Data(s.utf8)))?.arrayIfArray ?? []
        default: []
        }
    }
    private nonisolated var arrayIfArray: [JSON]? { if case .array(let a) = self { a } else { nil } }

    nonisolated var object: [String: JSON] { if case .object(let o) = self { o } else { [:] } }

    nonisolated var date: Date? { string.flatMap(DateCoding.parse) }

    /// Back to Foundation types (for request bodies).
    nonisolated var foundation: Any {
        switch self {
        case .null: NSNull()
        case .bool(let b): b
        case .number(let n): n
        case .string(let s): s
        case .array(let a): a.map(\.foundation)
        case .object(let o): o.mapValues(\.foundation)
        }
    }
}

nonisolated extension JSON: ExpressibleByStringLiteral, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral,
                ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    nonisolated init(stringLiteral v: String) { self = .string(v) }
    nonisolated init(floatLiteral v: Double) { self = .number(v) }
    nonisolated init(integerLiteral v: Int) { self = .number(Double(v)) }
    nonisolated init(booleanLiteral v: Bool) { self = .bool(v) }
    nonisolated init(arrayLiteral elements: JSON...) { self = .array(elements) }
    nonisolated init(dictionaryLiteral elements: (String, JSON)...) { self = .object(Dictionary(uniqueKeysWithValues: elements)) }
    nonisolated init(nilLiteral: ()) { self = .null }
}

nonisolated extension JSON {
    nonisolated static func from(_ s: String?) -> JSON { s.map(JSON.string) ?? .null }
    nonisolated static func from(_ d: Double?) -> JSON { d.map(JSON.number) ?? .null }

    /// Object literal that drops null values.
    nonisolated static func compact(_ pairs: [String: JSON]) -> JSON { .object(pairs.filter { !$0.value.isNull }) }
}
