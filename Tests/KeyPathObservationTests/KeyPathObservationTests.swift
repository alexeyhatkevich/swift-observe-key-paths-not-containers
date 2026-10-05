import Foundation
import Testing
import KeyPathObservation

// A profile container shaped like what an Objective-C store would hold.
private func profile(name: String = "Ann", biometrics: Bool = false, tags: [String] = ["a"]) -> [String: Any] {
    ["name": name, "settings": ["biometrics": biometrics, "theme": "dark"], "tags": tags]
}

// MARK: - KeyPathDiff

@Suite("KeyPathDiff")
struct KeyPathDiffTests {

    @Test func test_diff_nested_change_reports_full_path() {
        // A leaf two levels down is reported by its full dotted path, nothing else.
        let changed = KeyPathDiff.changedPaths(old: profile(), new: profile(biometrics: true), prefix: "Profile")
        #expect(changed == ["Profile.settings.biometrics"])
    }

    @Test func test_diff_equal_values_report_nothing() {
        // Re-writing the same value is not a change.
        #expect(KeyPathDiff.changedPaths(old: profile(), new: profile(), prefix: "Profile").isEmpty)
    }

    @Test func test_diff_missing_container_is_whole_container() {
        // First write (no old value) and delete (no new value) both change the whole container.
        #expect(KeyPathDiff.changedPaths(old: nil, new: profile(), prefix: "Profile") == ["Profile"])
        #expect(KeyPathDiff.changedPaths(old: profile(), new: nil, prefix: "Profile") == ["Profile"])
    }

    @Test func test_diff_array_is_a_leaf() {
        // Arrays are compared by equality; a change reports the array's own path.
        let changed = KeyPathDiff.changedPaths(old: profile(tags: ["a"]), new: profile(tags: ["a", "b"]), prefix: "Profile")
        #expect(changed == ["Profile.tags"])
    }

    @Test func test_diff_added_and_removed_keys() {
        // Keys present on only one side are reported as changed.
        let changed = KeyPathDiff.changedPaths(old: ["a": 1], new: ["b": 2], prefix: "C")
        #expect(changed == ["C.a", "C.b"])
    }

    @Test func test_diff_dictionary_replaced_by_scalar() {
        // A subtree replaced by a scalar reports the subtree's path.
        let changed = KeyPathDiff.changedPaths(old: ["s": ["x": 1]], new: ["s": "off"], prefix: "C")
        #expect(changed == ["C.s"])
    }

    @Test func test_diff_accepts_foundation_objects() {
        // NSDictionary / NSNumber from the Objective-C side diff the same way.
        let old = NSDictionary(dictionary: ["n": NSNumber(value: 1)])
        let new = NSDictionary(dictionary: ["n": NSNumber(value: 2)])
        #expect(KeyPathDiff.changedPaths(old: old, new: new, prefix: "C") == ["C.n"])
    }
}

// MARK: - PathMatcher

@Suite("PathMatcher")
struct PathMatcherTests {

    @Test func test_matcher_equal_paths() {
        // Same path: affected.
        #expect(PathMatcher.isAffected(read: "Profile.name", by: "Profile.name"))
    }

    @Test func test_matcher_reader_of_parent_sees_child_change() {
        // Reading `Profile.settings` must react to a change of `Profile.settings.biometrics`.
        #expect(PathMatcher.isAffected(read: "Profile.settings", by: "Profile.settings.biometrics"))
    }

    @Test func test_matcher_reader_of_child_sees_parent_replacement() {
        // Reading `Profile.settings.biometrics` must react when `Profile.settings` is replaced.
        #expect(PathMatcher.isAffected(read: "Profile.settings.biometrics", by: "Profile.settings"))
    }

    @Test func test_matcher_sibling_is_not_affected() {
        // A sibling key is not affected.
        #expect(!PathMatcher.isAffected(read: "Profile.name", by: "Profile.settings.biometrics"))
    }

    @Test func test_matcher_respects_dot_boundary() {
        // `Profile.nameColor` is not under `Profile.name`, despite the shared prefix.
        #expect(!PathMatcher.isAffected(read: "Profile.nameColor", by: "Profile.name"))
        #expect(!PathMatcher.isAffected(read: "Profile.name", by: "Profile.nameColor"))
    }

    @Test func test_matcher_nil_changed_paths_is_legacy_container_wide() {
        // `nil` changed paths: every reader of the container is affected (old behaviour).
        #expect(PathMatcher.isAffected(reads: ["Profile.name"], container: "Profile", changed: nil))
        #expect(!PathMatcher.isAffected(reads: ["Other.name"], container: "Profile", changed: nil))
    }
}

// MARK: - Stores

@Suite("Stores")
struct StoreTests {

    /// Builds a store with three elements and an initial profile.
    private func make<S: ObservableStore>(_ store: S) -> (S, name: Element, toggle: Element, settings: Element) {
        let name = Element(name: "greeting", template: "Hello, {{Profile.name}}")
        let toggle = Element(name: "toggle", reads: ["Profile.settings.biometrics"])
        let settings = Element(name: "settingsCard", reads: ["Profile.settings"])
        store.write("Profile", profile())
        [name, toggle, settings].forEach(store.observe)
        return (store, name, toggle, settings)
    }

    @Test func test_naive_sibling_change_redraws_everyone() {
        // The bug: flipping biometrics redraws the greeting that only reads the name.
        let (store, name, toggle, settings) = make(NaiveStore())
        store.write("Profile", profile(biometrics: true))
        #expect(name.redrawCount == 1)
        #expect(toggle.redrawCount == 1)
        #expect(settings.redrawCount == 1)
    }

    @Test func test_naive_identical_write_still_redraws() {
        // The bug: writing the same value again redraws every observer.
        let (store, name, _, _) = make(NaiveStore())
        store.write("Profile", profile())
        #expect(name.redrawCount == 1)
    }

    @Test func test_naive_lookalike_container_name_matches_by_substring() {
        // The bug: `ProfileDraft.title` contains "Profile", so it is redrawn by `Profile` writes.
        let store = NaiveStore()
        let lookalike = Element(name: "header", reads: ["ProfileDraft.title"])
        store.observe(lookalike)
        store.write("Profile", profile())
        #expect(lookalike.redrawCount == 1)
    }

    @Test func test_fixed_sibling_change_does_not_redraw() {
        // Flipping biometrics leaves the greeting alone.
        let (store, name, _, _) = make(FixedStore())
        store.write("Profile", profile(biometrics: true))
        #expect(name.redrawCount == 0)
    }

    @Test func test_fixed_nested_change_redraws_readers_of_path_and_parent() {
        // The toggle (exact path) and the card (parent path) both redraw.
        let (store, _, toggle, settings) = make(FixedStore())
        store.write("Profile", profile(biometrics: true))
        #expect(toggle.redrawCount == 1)
        #expect(settings.redrawCount == 1)
    }

    @Test func test_fixed_identical_write_redraws_nobody() {
        // No diff, no notification.
        let (store, name, toggle, settings) = make(FixedStore())
        store.write("Profile", profile())
        #expect([name, toggle, settings].allSatisfy { $0.redrawCount == 0 })
    }

    @Test func test_fixed_container_replaced_redraws_affected_readers() {
        // Replacing `settings` with a scalar reaches the reader of the nested key.
        let (store, name, toggle, _) = make(FixedStore())
        var p = profile()
        p["settings"] = "reset"
        store.write("Profile", p)
        #expect(toggle.redrawCount == 1)
        #expect(name.redrawCount == 0)
    }

    @Test func test_fixed_missing_container_redraws_all_readers() {
        // Deleting the container is a whole-container change.
        let (store, name, toggle, settings) = make(FixedStore())
        store.write("Profile", nil)
        #expect([name, toggle, settings].allSatisfy { $0.redrawCount == 1 })
    }

    @Test func test_fixed_array_change_redraws_array_reader_only() {
        // An array element change reports `Profile.tags`; only its reader redraws.
        let (store, name, _, _) = make(FixedStore())
        let tags = Element(name: "chips", reads: ["Profile.tags"])
        store.observe(tags)
        store.write("Profile", profile(tags: ["a", "b"]))
        #expect(tags.redrawCount == 1)
        #expect(name.redrawCount == 0)
    }

    @Test func test_fixed_lookalike_container_name_is_not_matched() {
        // Container matching is by the first path component, not by substring.
        let store = FixedStore()
        let lookalike = Element(name: "header", reads: ["ProfileDraft.title"])
        store.observe(lookalike)
        store.write("Profile", profile())
        #expect(lookalike.redrawCount == 0)
    }

    @Test func test_fixed_legacy_write_without_diff_is_container_wide() {
        // The escape hatch keeps the old behaviour for writers that cannot diff.
        let (store, name, toggle, settings) = make(FixedStore())
        store.writeWithoutDiff("Profile", profile())
        #expect([name, toggle, settings].allSatisfy { $0.redrawCount == 1 })
    }
}

// MARK: - Template parsing (the `Swift.Range` aside)

@Suite("TemplateReads")
struct TemplateReadsTests {

    @Test func test_template_reads_extracts_paths() {
        // Paths come out of `{{ … }}` placeholders, whitespace allowed.
        let reads = TemplateReads.paths(in: "Hi {{Profile.name}}, theme: {{ Profile.settings.theme }}")
        #expect(reads == ["Profile.name", "Profile.settings.theme"])
    }

    @Test func test_module_range_type_is_the_domain_struct() {
        // Inside the module (and for importers) unqualified `Range` is the domain struct.
        let r = KeyPathObservation.Range(minimum: 0, maximum: 10)
        #expect(r.maximum == 10)
    }
}
