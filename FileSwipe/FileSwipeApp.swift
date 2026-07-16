import SwiftUI

@main
struct FileSwipeApp: App {
    @StateObject private var queue = FileQueueManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(queue)
                .environmentObject(KeyboardPreferences.shared)
                .frame(minWidth: 720, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 900, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Review") {
                Button("Keep / Skip") {
                    queue.keepCurrent()
                }
                .disabled(queue.currentItem == nil)

                Button("Move to Trash") {
                    queue.deleteCurrent()
                }
                .disabled(queue.currentItem == nil)

                Divider()

                Button("Undo Last Action") {
                    queue.undoLast()
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!queue.canUndo)

                Button("Show in Finder") {
                    queue.revealCurrentInFinder()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(queue.currentItem == nil)

                Button("Quick Look") {
                    queue.quickLookCurrent()
                }
                .disabled(queue.currentItem == nil)

                Divider()

                Button("Done with This Folder") {
                    queue.done()
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(queue.folderURL == nil)
            }
        }
    }
}
