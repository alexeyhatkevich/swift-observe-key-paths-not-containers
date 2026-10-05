# Observe key paths, not containers

A data store keeps named JSON-like containers (`Profile`, `Cart`, …). UI elements
read key paths such as `Profile.settings.biometrics` but subscribe to the container
name `Profile`. Every write to `Profile` then redraws every element that reads
anything in it — even when the key it reads did not change. The result is extra
work, flicker and state resets on screens that have nothing to do with the write.

## How to run

**In Xcode (demo app + tests):**

1. Open `Demo/Demo.xcodeproj` (it uses this package as a local dependency).
2. Pick any iPhone simulator (iOS 17+) and press **⌘R**.
3. Use the **Naive / Fixed** switch at the top. Each row is a UI element showing
   what it reads and how many times it redrew; rows redrawn by the last write turn orange.
   - Tap **Flip Face ID**: in *Naive* every row redraws, including the greeting, the
     tag chips and the `ProfileDraft.title` header (substring match). In *Fixed* only
     the Face ID toggle and the settings card redraw.
   - Tap **Write the same Profile again**: *Naive* redraws everyone, *Fixed* nobody.
4. **⌘U** runs the package test suite (the `Demo` scheme includes `KeyPathObservationTests`).

**From the command line:** the library is plain Swift (Foundation only), so
`swift test` works on macOS as well.

This package reproduces the problem and the fix in pure Swift:

- `NaiveStore` — container-wide notification, plus substring name matching
  (`ProfileDraft.title` is "inside" `Profile`).
- `FixedStore` — diffs old vs new value at write time and redraws only elements
  whose read paths are affected.
- `KeyPathDiff.changedPaths(old:new:prefix:)` — recursive diff of dictionaries into
  dotted key paths. Arrays and scalars are leaves compared with `isEqual:`. A missing
  old or new value means the whole container changed. It is an `@objc` `NSObject`
  subclass, so an Objective-C store can call it on its write path.
- `PathMatcher.isAffected(read:by:)` — equal paths, or one is a prefix of the other
  at a `.` boundary. `nil` changed paths = legacy container-wide notification.
- `TemplateReads` — extracts read paths from `{{Profile.name}}` templates, and shows
  why a module type named `Range` forces you to write `Swift.Range(nsRange, in:)`.

## Run the tests

```bash
swift test
```

or **⌘U** in `Demo/Demo.xcodeproj`. Tests named `test_naive_…` assert the broken behaviour (they pass and document the
bug); `test_fixed_…` assert the fix; `test_diff_…`, `test_matcher_…` cover the
edge cases: sibling change, nested change, container replaced, missing container,
array change, look-alike container names and the `nil` legacy fallback.

## License

MIT

Write-up: https://alexeyhatkevich.blogspot.com
