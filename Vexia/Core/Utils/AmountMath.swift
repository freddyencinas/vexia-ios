import Foundation

/// Exact math for asset quantities (BTC has 8 decimals; Double drifts: 0.1 + 0.2 ≠ 0.3).
nonisolated enum AmountMath {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// Separator the decimal keyboard types, so edited text round-trips.
    static var separator: String { Locale.current.decimalSeparator ?? "," }

    /// Keeps digits and a single decimal separator, cutting decimals beyond `maxDecimals` while typing.
    static func sanitize(_ s: String, maxDecimals: Int) -> String {
        var out = "", seenSeparator = false, decimals = 0
        for ch in s {
            if ch.isASCII && ch.isNumber {
                if seenSeparator {
                    guard decimals < maxDecimals else { continue }
                    decimals += 1
                }
                out.append(ch)
            } else if (ch == "," || ch == "."), !seenSeparator, maxDecimals > 0 {
                seenSeparator = true
                out += (out.isEmpty ? "0" : "") + String(ch)
            }
        }
        return out
    }

    /// Locale-tolerant: "0,5", "0.5", "1.234,5", "1,234.5".
    static func parse(_ s: String) -> Decimal? {
        var t = s.filter { "0123456789.,".contains($0) }
        guard !t.isEmpty else { return nil }
        if let c = t.lastIndex(of: ","), let d = t.lastIndex(of: ".") {
            t = c > d ? t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                      : t.replacingOccurrences(of: ",", with: "")
        } else {
            t = t.replacingOccurrences(of: ",", with: ".")
        }
        return Decimal(string: t, locale: posix)
    }

    static func rounded(_ d: Decimal, scale: Int, mode: NSDecimalNumber.RoundingMode = .down) -> Decimal {
        var value = d, result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }

    /// Plain editable text ("0,00352"), no grouping, trailing zeros trimmed.
    static func editable(_ d: Decimal, maxDecimals: Int) -> String {
        NSDecimalNumber(decimal: rounded(d, scale: maxDecimals, mode: .plain)).stringValue
            .replacingOccurrences(of: ".", with: separator)
    }

    /// Units bought with `fiat`, rounded down so the cost never exceeds what was typed.
    static func units(fromFiat fiat: Decimal, price: Decimal, maxDecimals: Int) -> Decimal {
        guard price > 0 else { return 0 }
        return rounded(fiat / price, scale: maxDecimals)
    }

    static func fiat(units: Decimal, price: Decimal) -> Decimal { rounded(units * price, scale: 2, mode: .plain) }

    /// Share of a holding; 100 % returns it exactly so "Máx" never leaves dust.
    static func portion(of available: Decimal, percent: Int, maxDecimals: Int) -> Decimal {
        percent >= 100 ? available : rounded(available * Decimal(percent) / 100, scale: maxDecimals)
    }

    /// Via the shortest description: Decimal(0.1) would carry binary noise.
    static func decimal(_ v: Double) -> Decimal { Decimal(string: "\(v)", locale: posix) ?? Decimal(v) }
    static func double(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }
}
