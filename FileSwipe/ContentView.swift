import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var queue: FileQueueManager
    @EnvironmentObject private var keyboardPrefs: KeyboardPreferences
    @FocusState private var isFocused: Bool
    @State private var showKeyboardSettings = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            mainArea
            Divider()
            bottomBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        // Keyboard keep/delete only when the user turns it on in settings
        .onKeyPress { press in
            guard let action = keyboardPrefs.action(for: press) else {
                return .ignored
            }
            guard queue.currentItem != nil else { return .ignored }
            switch action {
            case .keep:
                queue.keepCurrent()
            case .delete:
                queue.deleteCurrent()
            }
            return .handled
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { queue.errorMessage = nil }
        } message: {
            Text(queue.errorMessage ?? "")
        }
        .sheet(isPresented: $showKeyboardSettings) {
            KeyboardSettingsView(preferences: keyboardPrefs)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { queue.errorMessage != nil },
            set: { if !$0 { queue.errorMessage = nil } }
        )
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("FileSwipe")
                    .font(.headline)
                if let folder = queue.folderURL {
                    Text(folder.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Pick a folder and swipe through its files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if queue.folderURL != nil {
                Picker("Sort", selection: $queue.sortMode) {
                    ForEach(FileQueueManager.SortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                .help("Order of cards. “Newest added” matches Downloads sorted by Date Added (not Date Modified).")
                .onChange(of: queue.sortMode) { _, _ in
                    queue.reload()
                }
            }

            Button {
                showKeyboardSettings = true
            } label: {
                Image(systemName: "keyboard")
            }
            .help("Keyboard shortcuts (off by default)")

            if queue.folderURL != nil {
                Button("Done") {
                    queue.done()
                }
                .help("Stop reviewing and go pick a folder")
                .keyboardShortcut("d", modifiers: [.command])
            }

            Button("Downloads") {
                queue.loadDownloads()
            }

            Button("Choose Folder…") {
                queue.pickFolder()
            }
            .keyboardShortcut("o", modifiers: [.command])
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Main

    @ViewBuilder
    private var mainArea: some View {
        if queue.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Scanning folder…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if queue.folderURL == nil {
            emptyStart
        } else if queue.isEmptyFolder {
            emptyFolderView
        } else if queue.isFinished {
            finishedView
        } else if let item = queue.currentItem {
            ZStack {
                // Faint next card behind
                if queue.currentIndex + 1 < queue.items.count {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                        .padding(28)
                        .offset(y: 10)
                        .scaleEffect(0.97)
                }

                SwipeCardView(
                    item: item,
                    onKeep: { queue.keepCurrent() },
                    onDelete: { queue.deleteCurrent() }
                )
                .id(item.id)
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            emptyStart
        }
    }

    private var emptyStart: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.stack.badge.person.crop")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)

            Text("Swipe through a messy folder")
                .font(.title2.weight(.semibold))

            VStack(spacing: 8) {
                Text("→  Swipe right to keep")
                Text("←  Swipe left to trash")
                Text("Or use the Keep / Delete buttons")
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Text("Nothing is permanently deleted — trash goes to the Mac Trash.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            HStack(spacing: 12) {
                Button("Open Downloads") {
                    queue.loadDownloads()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Choose Folder…") {
                    queue.pickFolder()
                }
                .controlSize(.large)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var emptyFolderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)

            Text("This folder is empty")
                .font(.title2.weight(.semibold))

            if let path = queue.folderURL?.path {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            HStack(spacing: 12) {
                Button("Done") {
                    queue.done()
                }
                Button("Open Downloads") {
                    queue.loadDownloads()
                }
                Button("Choose another folder") {
                    queue.pickFolder()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var finishedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("All done")
                .font(.title2.weight(.semibold))

            Text("Kept \(queue.keptCount) · Moved \(queue.deletedCount) to Trash")
                .foregroundStyle(.secondary)

            // Primary exit path
            Button {
                queue.done()
            } label: {
                Text("Done")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 8)

            HStack(spacing: 12) {
                if queue.canUndo {
                    Button("Undo last") {
                        queue.undoLast()
                    }
                }
                Button("Review this folder again") {
                    queue.reload()
                }
                Button("Choose another folder") {
                    queue.pickFolder()
                }
                Button("Open Downloads") {
                    queue.loadDownloads()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            Button {
                queue.deleteCurrent()
            } label: {
                Label("Delete", systemImage: "trash")
                    .frame(minWidth: 100)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(queue.currentItem == nil)

            VStack(spacing: 4) {
                Text(queue.progressText)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()

                if queue.folderURL != nil && !queue.items.isEmpty && !queue.isFinished {
                    ProgressView(
                        value: Double(queue.currentIndex),
                        total: Double(max(queue.items.count, 1))
                    )
                    .frame(width: 180)
                }

                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Button {
                queue.keepCurrent()
            } label: {
                Label("Keep", systemImage: "checkmark")
                    .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(queue.currentItem == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if queue.folderURL != nil {
                HStack(spacing: 16) {
                    if queue.currentItem != nil {
                        Button("Undo") { queue.undoLast() }
                            .disabled(!queue.canUndo)
                        Button("Quick Look") { queue.quickLookCurrent() }
                        Button("Show in Finder") { queue.revealCurrentInFinder() }
                        Button("Open") { queue.openCurrentWithDefaultApp() }
                        Button("Keyboard…") { showKeyboardSettings = true }
                        Divider()
                            .frame(height: 12)
                        Button("Stop early") { queue.finishEarly() }
                            .help("Skip the rest and see your summary")
                    }
                    Button("Done") { queue.done() }
                        .help("Exit and pick a different folder")
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .padding(.bottom, 10)
            }
        }
    }

    private var statusLine: String {
        var parts = ["Kept \(queue.keptCount) · Deleted \(queue.deletedCount)"]
        if keyboardPrefs.isEnabled {
            parts.append("Keys: keep \(keyboardPrefs.keepKey.shortLabel) · delete \(keyboardPrefs.deleteKey.shortLabel)")
        }
        return parts.joined(separator: "  ·  ")
    }
}

#Preview {
    ContentView()
        .environmentObject(FileQueueManager())
        .environmentObject(KeyboardPreferences.shared)
        .frame(width: 900, height: 700)
}
