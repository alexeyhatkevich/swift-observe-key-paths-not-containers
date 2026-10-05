import Foundation

/// A UI element that reads some key paths and redraws when told to.
public final class Element {
    public let name: String
    /// Key paths this element reads, e.g. `["Profile.settings.biometrics"]`.
    public let reads: [String]
    /// How many times the element re-ran its load actions and redrew.
    public private(set) var redrawCount = 0

    public init(name: String, reads: [String]) {
        self.name = name
        self.reads = reads
    }

    /// Convenience: derive the read paths from a display template such as
    /// `"Hello, {{Profile.name}}"`.
    public convenience init(name: String, template: String) {
        self.init(name: name, reads: TemplateReads.paths(in: template))
    }

    func redraw() { redrawCount += 1 }
}

/// A store of named JSON-like containers that notifies observing elements on writes.
public protocol ObservableStore: AnyObject {
    func observe(_ element: Element)
    func write(_ container: String, _ value: Any?)
    func value(of container: String) -> Any?
}

/// The original behaviour: an element observes the container *name*, and every
/// write to it redraws every observer.
///
/// The name lookup is also a plain substring check, so an element reading
/// `ProfileDraft.title` is redrawn by writes to `Profile` too.
public final class NaiveStore: ObservableStore {
    private var containers: [String: Any] = [:]
    private var observers: [Element] = []

    public init() {}

    public func observe(_ element: Element) { observers.append(element) }

    public func value(of container: String) -> Any? { containers[container] }

    public func write(_ container: String, _ value: Any?) {
        containers[container] = value
        for element in observers where element.reads.contains(where: { $0.contains(container) }) {
            element.redraw()
        }
    }
}

/// The fix: diff old vs new at write time and redraw only the elements whose read
/// paths are affected by one of the changed paths.
public final class FixedStore: ObservableStore {
    private var containers: [String: Any] = [:]
    private var observers: [Element] = []

    public init() {}

    public func observe(_ element: Element) { observers.append(element) }

    public func value(of container: String) -> Any? { containers[container] }

    public func write(_ container: String, _ value: Any?) {
        let old = containers[container]
        containers[container] = value
        let changed = KeyPathDiff.changedPaths(old: old, new: value, prefix: container)
        guard !changed.isEmpty else { return }
        notify(container: container, changed: changed)
    }

    /// Legacy escape hatch for writers that cannot (or do not yet) diff: store the
    /// value and notify with `nil` changed paths, i.e. container-wide.
    public func writeWithoutDiff(_ container: String, _ value: Any?) {
        containers[container] = value
        notify(container: container, changed: nil)
    }

    private func notify(container: String, changed: [String]?) {
        for element in observers
        where PathMatcher.isAffected(reads: element.reads, container: container, changed: changed) {
            element.redraw()
        }
    }
}
