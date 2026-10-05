import SwiftUI
import KeyPathObservation

/// Which store implementation the screen is wired to.
enum Mode: String, CaseIterable, Identifiable {
    case naive = "Naive"
    case fixed = "Fixed"
    var id: String { rawValue }
}

/// Builds the `Profile` container the same way the package tests do.
private func profile(name: String, biometrics: Bool, tags: [String]) -> [String: Any] {
    ["name": name, "settings": ["biometrics": biometrics, "theme": "dark"], "tags": tags]
}

/// One store plus the elements observing it. Rebuilt whenever the mode changes.
@MainActor
final class DemoModel: ObservableObject {
    @Published private(set) var mode: Mode = .naive
    @Published private(set) var lastAction = "Tap a button below."
    @Published private(set) var lastRedrawn: Set<String> = []

    private(set) var store: ObservableStore = NaiveStore()
    private(set) var elements: [Element] = []

    private var name = "Ann"
    private var biometrics = false
    private var tags = ["swift"]

    init() { reset(mode: .naive) }

    func reset(mode: Mode) {
        self.mode = mode
        name = "Ann"; biometrics = false; tags = ["swift"]
        store = mode == .naive ? NaiveStore() : FixedStore()
        store.write("Profile", currentProfile)
        elements = [
            Element(name: "Greeting", template: "Hello, {{Profile.name}}"),
            Element(name: "Face ID toggle", reads: ["Profile.settings.biometrics"]),
            Element(name: "Settings card", reads: ["Profile.settings"]),
            Element(name: "Tag chips", reads: ["Profile.tags"]),
            Element(name: "Draft header", reads: ["ProfileDraft.title"]),
        ]
        elements.forEach(store.observe)
        lastAction = "Store reset (\(mode.rawValue)). All counters at 0."
        lastRedrawn = []
    }

    private var currentProfile: [String: Any] {
        profile(name: name, biometrics: biometrics, tags: tags)
    }

    func flipBiometrics() {
        biometrics.toggle()
        write("Profile.settings.biometrics = \(biometrics)")
    }

    func rename() {
        name = name == "Ann" ? "Bob" : "Ann"
        write("Profile.name = \"\(name)\"")
    }

    func addTag() {
        tags.append("tag\(tags.count)")
        write("Profile.tags appended")
    }

    func writeSame() {
        write("same Profile written again")
    }

    private func write(_ description: String) {
        let before = elements.map(\.redrawCount)
        store.write("Profile", currentProfile)
        lastRedrawn = Set(zip(elements, before).filter { $0.redrawCount != $1 }.map(\.0.name))
        lastAction = "Wrote \(description) -> \(lastRedrawn.count) of \(elements.count) redrawn."
    }
}

struct ContentView: View {
    @StateObject private var model = DemoModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Store", selection: Binding(
                        get: { model.mode },
                        set: { model.reset(mode: $0) }
                    )) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("modePicker")
                } footer: {
                    Text(model.mode == .naive
                         ? "Naive: every write to Profile redraws every element that subscribed to the container name. \"ProfileDraft\" also matches, because the name check is a substring."
                         : "Fixed: the store diffs old vs new and redraws only elements whose read paths overlap a changed path.")
                }

                Section("Elements (what each one reads)") {
                    ForEach(model.elements, id: \.name) { element in
                        ElementRow(element: element, justRedrawn: model.lastRedrawn.contains(element.name))
                    }
                }

                Section {
                    Button("Flip Face ID (Profile.settings.biometrics)", action: model.flipBiometrics)
                    Button("Rename (Profile.name)", action: model.rename)
                    Button("Add tag (Profile.tags)", action: model.addTag)
                    Button("Write the same Profile again", action: model.writeSame)
                    Button("Reset counters", role: .destructive) { model.reset(mode: model.mode) }
                } header: {
                    Text("Writes")
                } footer: {
                    Text(model.lastAction).font(.footnote.monospaced())
                }

                Section("What to watch") {
                    Text("Tap \"Flip Face ID\". In Naive, Greeting, Tag chips and Draft header redraw too (highlighted orange) although nothing they read changed. In Fixed, only Face ID toggle and Settings card redraw. \"Write the same Profile again\" redraws everyone in Naive and nobody in Fixed.")
                        .font(.callout)
                }
            }
            .navigationTitle("Observe key paths")
        }
    }
}

private struct ElementRow: View {
    let element: Element
    let justRedrawn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(element.name).font(.body.weight(.semibold))
                Text(element.reads.joined(separator: ", "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(element.redrawCount)")
                .font(.title3.monospacedDigit().weight(.bold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(justRedrawn ? Color.orange.opacity(0.85) : Color.secondary.opacity(0.15),
                            in: Capsule())
                .foregroundStyle(justRedrawn ? .white : .primary)
                .accessibilityLabel("\(element.name) redraws \(element.redrawCount)")
        }
        .animation(.easeOut(duration: 0.25), value: element.redrawCount)
    }
}
