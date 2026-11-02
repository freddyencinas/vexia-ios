import Foundation

/// Money/date/quantity formatting helpers.
enum Fmt {
    /// Local currency symbols (design: "$1.539,00", "Bs 100,00"); unknown codes fall back to "100,00 CODE".
    nonisolated static let symbols: [String: String] = [
        "USD": "$", "BOB": "Bs", "VES": "Bs", "EUR": "€", "ARS": "$a", "CLP": "$", "COP": "$", "MXN": "$",
        "PEN": "S/", "BRL": "R$", "GBP": "£", "USDT": "₮", "USDC": "USDC", "BTC": "₿",
    ]

    static func symbol(_ code: String) -> String? { symbols[code.uppercased()] }

    /// Spanish grouping in every app language (regional design: "1.539,00"; ICU's `es` would print "1539,00").
    /// Holding quantity: crypto keeps 4 decimals; shares show whole numbers as-is and fractions
    /// with up to 4 decimals (0,7 → "0,70", 2,3333 → "2,3333") — never rounds 0,70 shares to "1".
    nonisolated static func quantity(_ v: Double, crypto: Bool) -> String {
        if crypto { return grouped(v, decimals: 4) }
        if abs(v - v.rounded()) < 1e-9 { return grouped(v, decimals: 0) }
        var s = grouped(v, decimals: 4)
        while s.hasSuffix("0"), let comma = s.firstIndex(of: ","), s.distance(from: comma, to: s.endIndex) > 3 { s.removeLast() }
        return s
    }

    nonisolated static func grouped(_ v: Double, decimals: Int = 2) -> String {
        let s = String(format: "%.\(decimals)f", abs(v))
        let parts = s.split(separator: ".")
        var intPart = String(parts[0])
        var out = ""
        while intPart.count > 3 { out = "." + intPart.suffix(3) + out; intPart = String(intPart.dropLast(3)) }
        out = intPart + out
        return parts.count > 1 ? out + "," + parts[1] : out
    }

    static func money(_ amount: Double, currency: String = "USD", compact: Bool = false) -> String {
        let code = currency.uppercased()
        let sign = amount < 0 ? "−" : ""
        var body: String
        if compact, abs(amount) >= 10_000 {
            let (v, unit) = abs(amount) >= 1_000_000 ? (abs(amount) / 1_000_000, " M")
                : (abs(amount) / 1_000, " " + String(localized: "mil", comment: "Thousands suffix in compact amounts: 17,2 mil"))
            body = grouped(v, decimals: v < 100 ? 1 : 0).replacingOccurrences(of: ",0", with: "") + unit
        } else {
            body = grouped(amount)
        }
        guard let sym = symbol(code) else { return "\(sign)\(body) \(code)" }
        // Letter symbols get a space ("Bs 100,00"); glyph symbols don't ("$100,00").
        let spaced = sym.first?.isLetter == true && sym.count > 1
        return sign + sym + (spaced ? " " : "") + body
    }

    static func number(_ v: Double, digits: ClosedRange<Int> = 0...2) -> String {
        v.formatted(.number.precision(.fractionLength(digits)))
    }

    /// For editable text fields: no grouping separators (avoids "1.234" being re-parsed as 1.234).
    static func editable(_ v: Double, digits: ClosedRange<Int> = 0...2) -> String {
        v.formatted(.number.grouping(.never).precision(.fractionLength(digits)))
    }

    static func percent(_ v: Double, isFraction: Bool = false) -> String {
        let value = isFraction ? v : v / 100
        return value.formatted(.percent.precision(.fractionLength(0...1)))
    }

    static func signedMoney(_ amount: Double, currency: String, isIncome: Bool) -> String {
        (isIncome ? "+" : "−") + money(abs(amount), currency: currency)
    }

    static func shortDate(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated)) }
    /// Capitalized month name in the app language ("Octubre" / "October").
    static func monthName(_ d: Date) -> String {
        d.formatted(.dateTime.month(.wide).locale(.current)).capitalizedFirst
    }
    static func monthYearES(_ d: Date) -> String {
        d.formatted(.dateTime.month(.wide).year().locale(.current)).capitalizedFirst
    }
    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    static func monthYear(_ d: Date) -> String { d.formatted(.dateTime.month(.wide).year()) }
}

nonisolated enum DateCoding {
    nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    nonisolated(unsafe) static let isoNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    nonisolated static let day: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f
    }()

    nonisolated static func parse(_ s: String) -> Date? {
        iso.date(from: s) ?? isoNoFraction.date(from: s) ?? day.date(from: String(s.prefix(10)))
    }
    nonisolated static func dayString(_ d: Date) -> String { day.string(from: d) }
}

extension String {
    /// "domingo, 1 de noviembre" → "Domingo, 1 de noviembre" (Spanish keeps the rest lowercase).
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
