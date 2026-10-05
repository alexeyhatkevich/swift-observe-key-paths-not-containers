import Foundation

/// A domain type that happens to be called `Range` (e.g. a slider's allowed values).
///
/// Because it lives in this module, every unqualified `Range` inside the module now
/// means *this* struct, not `Swift.Range`. See `TemplateReads` for the consequence.
public struct Range: Equatable, Sendable {
    public var minimum: Double
    public var maximum: Double

    public init(minimum: Double, maximum: Double) {
        self.minimum = minimum
        self.maximum = maximum
    }
}

/// Extracts the key paths a display template reads: `"Hi {{Profile.name}}"` → `["Profile.name"]`.
public enum TemplateReads {
    // Compiled once; NSRegularExpression is immutable and thread-safe.
    nonisolated(unsafe) private static let pattern = try! NSRegularExpression(
        pattern: #"\{\{\s*([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*)\s*\}\}"#
    )

    public static func paths(in template: String) -> [String] {
        let whole = NSRange(template.startIndex..., in: template)
        return pattern.matches(in: template, range: whole).compactMap { match in
            // `Range(match.range(at: 1), in: template)` does not compile here:
            // the module's own `Range` struct shadows `Swift.Range`. Qualify it.
            guard let range = Swift.Range(match.range(at: 1), in: template) else { return nil }
            return String(template[range])
        }
    }
}
