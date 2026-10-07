import Foundation

/// Typed numbers for a goal's metric: lenient about spaces, grouping and the locale's decimal mark.
enum MetricInput {
    /// The number in `text`, or nil when it isn't one (or isn't finite).
    static func number(_ text: String, locale: Locale = .current) -> Double? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let decimal = locale.decimalSeparator ?? "."
        let grouping = locale.groupingSeparator ?? ","
        s = s.filter { !$0.isWhitespace && $0 != "\u{00A0}" && $0 != "\u{202F}" && $0 != "'" }
        if !grouping.isEmpty, grouping != decimal { s = s.replacingOccurrences(of: grouping, with: "") }
        if decimal != "." { s = s.replacingOccurrences(of: decimal, with: ".") }
        s = s.replacingOccurrences(of: "\u{2212}", with: "-")
        guard s.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" }), let value = Double(s), value.isFinite else { return nil }
        return value
    }

    /// Short and readable: grouping, at most two decimals, no trailing zeros.
    static func format(_ value: Double, locale: Locale = .current) -> String {
        guard value.isFinite else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    /// "12 km", "8,600 USD", or just the number.
    static func format(_ value: Double, unit: String, locale: Locale = .current) -> String {
        let u = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return u.isEmpty ? format(value, locale: locale) : "\(format(value, locale: locale)) \(u)"
    }

    /// The editable text for an optional number.
    static func text(_ value: Double?, locale: Locale = .current) -> String {
        value.map { format($0, locale: locale) } ?? ""
    }
}
