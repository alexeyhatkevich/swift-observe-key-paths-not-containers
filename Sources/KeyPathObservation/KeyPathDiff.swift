import Foundation

/// Computes which key paths changed between two values of a data container.
///
/// Values are JSON-like Foundation graphs (`NSDictionary` / `NSArray` / `NSString` /
/// `NSNumber`), exactly what an Objective-C data store hands over. The class is
/// `@objc` so the Objective-C write path can call it directly:
///
///     NSArray<NSString *> *changed =
///         [KeyPathDiff changedPathsWithOld:oldValue new:newValue prefix:@"Profile"];
@objc(KeyPathDiff)
public final class KeyPathDiff: NSObject {

    /// Returns the sorted list of changed key paths, each starting with `prefix`.
    ///
    /// - Both values dictionaries: recurse key by key.
    /// - Anything else (arrays, strings, numbers, a dictionary replaced by a scalar)
    ///   is a leaf compared with `isEqual:`; a changed leaf reports its own path.
    /// - A missing old or new value means the whole `prefix` changed.
    /// - Equal values return an empty list.
    @objc(changedPathsWithOld:new:prefix:)
    public static func changedPaths(old: Any?, new: Any?, prefix: String) -> [String] {
        var result: [String] = []
        collect(old: old, new: new, path: prefix, into: &result)
        return result.sorted()
    }

    private static func collect(old: Any?, new: Any?, path: String, into result: inout [String]) {
        switch (old, new) {
        case (nil, nil):
            return
        case (nil, _), (_, nil):
            result.append(path)
        case let (oldDict as [String: Any], newDict as [String: Any]):
            let keys = Set(oldDict.keys).union(newDict.keys)
            for key in keys {
                collect(old: oldDict[key], new: newDict[key], path: path + "." + key, into: &result)
            }
        case let (oldValue?, newValue?):
            if !(oldValue as AnyObject).isEqual(newValue as AnyObject) {
                result.append(path)
            }
        }
    }
}
