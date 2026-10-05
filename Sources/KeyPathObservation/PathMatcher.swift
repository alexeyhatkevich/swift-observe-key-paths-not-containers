import Foundation

/// Decides whether an element that reads a key path must react to a change.
public enum PathMatcher {

    /// The container a key path belongs to: everything before the first `.`.
    public static func container(of path: String) -> Substring {
        path.split(separator: ".", maxSplits: 1).first ?? Substring(path)
    }

    /// `true` when `read` and `changed` are equal, or one is a prefix of the other
    /// at a `.` boundary.
    ///
    ///     isAffected(read: "Profile.settings", by: "Profile.settings.biometrics")  // true
    ///     isAffected(read: "Profile.settings.biometrics", by: "Profile.settings")  // true
    ///     isAffected(read: "Profile.name", by: "Profile.settings")                 // false
    ///     isAffected(read: "Profile.nameColor", by: "Profile.name")                // false
    public static func isAffected(read: String, by changed: String) -> Bool {
        read == changed
            || read.hasPrefix(changed + ".")
            || changed.hasPrefix(read + ".")
    }

    /// Element-level check. `changed == nil` is the legacy signal from a writer that
    /// could not diff: every reader of the container is affected.
    public static func isAffected(reads: [String], container: String, changed: [String]?) -> Bool {
        let ownReads = reads.filter { self.container(of: $0) == container }
        guard !ownReads.isEmpty else { return false }
        guard let changed else { return true }
        return ownReads.contains { read in changed.contains { isAffected(read: read, by: $0) } }
    }
}
