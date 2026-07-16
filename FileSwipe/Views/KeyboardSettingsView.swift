import SwiftUI

struct KeyboardSettingsView: View {
    @ObservedObject var preferences: KeyboardPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var recordingFor: RecordingTarget?

    private enum RecordingTarget {
        case keep
        case delete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            Form {
                Section {
                    Toggle("Enable keyboard shortcuts", isOn: $preferences.isEnabled)

                    Text("Off by default. Swipe and the Keep / Delete buttons always work.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Keys") {
                    keyRow(
                        title: "Keep",
                        subtitle: "Skip this file and leave it where it is",
                        key: preferences.keepKey,
                        target: .keep,
                        tint: .green
                    )

                    keyRow(
                        title: "Delete",
                        subtitle: "Move this file to Trash",
                        key: preferences.deleteKey,
                        target: .delete,
                        tint: .red
                    )
                }
                .disabled(!preferences.isEnabled)

                if preferences.isEnabled {
                    Section {
                        if preferences.keepKey == preferences.deleteKey {
                            Label(
                                "Keep and Delete are set to the same key. Pick two different keys.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.orange)
                            .font(.callout)
                        }

                        Text("Click “Press a key…”, then tap the key you want. Avoid keys you need for typing elsewhere.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.bottom, 12)
        }
        .frame(width: 440, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        // Capture the next key while recording
        .focusable()
        .onKeyPress { press in
            guard let target = recordingFor else { return .ignored }
            // Don't capture modifier-only combos
            if !press.modifiers.subtracting([.numericPad, .function]).isEmpty {
                return .ignored
            }
            guard let key = AssignableKey.from(press: press) else {
                return .handled
            }
            switch target {
            case .keep:
                preferences.keepKey = key
            case .delete:
                preferences.deleteKey = key
            }
            recordingFor = nil
            return .handled
        }
    }

    private func keyRow(
        title: String,
        subtitle: String,
        key: AssignableKey,
        target: RecordingTarget,
        tint: Color
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(tint)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(key.shortLabel)
                .font(.body.monospaced())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12))
                )

            Button(recordingFor == target ? "Listening…" : "Press a key…") {
                recordingFor = target
            }
            .buttonStyle(.bordered)
            .tint(recordingFor == target ? .accentColor : nil)

            Picker("Choose \(title) key", selection: binding(for: target)) {
                ForEach(AssignableKey.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 36)
            .help("Or pick from a list")
        }
    }

    private func binding(for target: RecordingTarget) -> Binding<AssignableKey> {
        switch target {
        case .keep:
            Binding(
                get: { preferences.keepKey },
                set: { preferences.keepKey = $0 }
            )
        case .delete:
            Binding(
                get: { preferences.deleteKey },
                set: { preferences.deleteKey = $0 }
            )
        }
    }
}

#Preview {
    KeyboardSettingsView(preferences: KeyboardPreferences.shared)
}
