import Foundation

enum VersionComparator {
    static func normalize(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let core = trimmed.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? trimmed
        let numericComponents = core.split(separator: ".").map(String.init)
            .filter { Int($0) != nil }
        guard !numericComponents.isEmpty else { return "0" }

        let lastNonZeroIndex = numericComponents.lastIndex { Int($0) != 0 }
        guard let lastNonZeroIndex else { return "0" }
        return numericComponents[...lastNonZeroIndex].joined(separator: ".")
    }

    static func isNewer(_ candidate: String, than baseline: String) -> Bool {
        let candidateNormalized = normalize(candidate)
        let baselineNormalized = normalize(baseline)
        return candidateNormalized.compare(baselineNormalized, options: .numeric) == .orderedDescending
    }
}
