import Foundation

// Pure serving⇄gram arithmetic for the result screen's per-food serving rows
// (serving-adjust PRD, iOS Req 1/3). Lives in Foods beside `SolidServing` so
// the executed MedataCore suite covers the maths — the app layer only lays
// out what these functions produce.
public enum ServingMath {

    public static func grams(servings: Double, gramsPerUnit: Double) -> Double {
        max(0, servings * gramsPerUnit)
    }

    public static func servings(grams: Double, gramsPerUnit: Double) -> Double {
        guard gramsPerUnit > 0 else { return 0 }
        return max(0, grams / gramsPerUnit)
    }

    // Nearest displayable half-unit, floored at 0. Display granularity is half
    // a serving regardless of the class's stepper `step` — "≈ 1½ potatoes",
    // never "≈ 1.72 potatoes".
    public static func displayHalfUnits(_ count: Double) -> Double {
        max(0, (count * 2).rounded() / 2)
    }

    // Half-unit count as display text using the vulgar half fraction:
    // 0 → "0", 0.5 → "½", 1 → "1", 1.5 → "1½", 2 → "2".
    public static func halfUnitText(_ count: Double) -> String {
        let halves = Int((max(0, count) * 2).rounded())
        let whole = halves / 2
        if halves % 2 == 1 {
            return whole == 0 ? "½" : "\(whole)½"
        }
        return "\(whole)"
    }

    // Singular for exactly half or exactly one ("½ potato", "1 potato");
    // plural otherwise ("0 potatoes", "1½ potatoes", "3 heaped tablespoons").
    public static func unitLabel(count: Double, singular: String, plural: String) -> String {
        let halves = Int((max(0, count) * 2).rounded())
        return (halves == 1 || halves == 2) ? singular : plural
    }
}

// Machine-readable per-class serving note (serving-adjust PRD, iOS Req 4),
// extending the legacy `portion N/M` convention with a distinct prefix so the
// two never collide: a `servings` stamp carries one space-separated
// `class=value` token per row, where a bare number is a serving count and a
// `g` suffix marks a gram amount (rows without a serving unit, and liquids).
// Class ids are snake_case, so `=` and space are safe separators.
//
//   servings potato_boiled=1.5 peas=3 water=120g
public enum ServingNote {
    public enum Amount: Equatable, Sendable {
        case servings(Double)
        case grams(Double)
    }

    private static let prefix = "servings "

    public static func note(_ amounts: [(classId: String, amount: Amount)]) -> String {
        let tokens = amounts.map { entry in
            switch entry.amount {
            case .servings(let count): "\(entry.classId)=\(trimmed(count))"
            case .grams(let grams): "\(entry.classId)=\(trimmed(grams))g"
            }
        }
        return prefix + tokens.joined(separator: " ")
    }

    public static func parse(_ note: String) -> [String: Amount]? {
        guard note.hasPrefix(prefix) else { return nil }
        var amounts: [String: Amount] = [:]
        for token in note.dropFirst(prefix.count).split(separator: " ") {
            let parts = token.split(separator: "=")
            guard parts.count == 2 else { return nil }
            var value = String(parts[1])
            let isGrams = value.hasSuffix("g")
            if isGrams { value.removeLast() }
            guard let number = Double(value), number >= 0, number.isFinite else { return nil }
            amounts[String(parts[0])] = isGrams ? .grams(number) : .servings(number)
        }
        return amounts.isEmpty ? nil : amounts
    }

    // Two-decimal cap, whole numbers without a point: 2 → "2", 1.5 → "1.5",
    // 1.7241 → "1.72".
    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(rounded)
    }
}
