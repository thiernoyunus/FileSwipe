import AppKit
import Combine
import Darwin
import Foundation
import QuickLookUI

@MainActor
final class FileQueueManager: ObservableObject {
    @Published private(set) var folderURL: URL?
    @Published private(set) var items: [FileItem] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var keptCount: Int = 0
    @Published private(set) var deletedCount: Int = 0
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var sortMode: SortMode = .newestAdded

    enum SortMode: String, CaseIterable, Identifiable {
        /// Matches Finder Downloads sorted by Date Added (not Date Modified).
        case newestAdded = "Newest added"
        case oldestAdded = "Oldest added"
        case largestFirst = "Largest first"
        case nameAZ = "Name A–Z"

        var id: String { rawValue }
    }

    private struct HistoryEntry {
        enum Action {
            case kept
            case deleted(originalURL: URL, trashURL: URL?)
        }

        let item: FileItem
        let action: Action
        let indexBefore: Int
    }

    private var history: [HistoryEntry] = []
    private let maxHistory = 100
    private let fileManager = FileManager.default
    /// Keeps security-scoped folder access alive while the folder is open.
    private var securityScopedFolder: URL?

    var currentItem: FileItem? {
        guard currentIndex >= 0, currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    var remainingCount: Int {
        max(0, items.count - currentIndex)
    }

    var progressText: String {
        guard !items.isEmpty else { return "No files" }
        if currentIndex >= items.count {
            return "Done — \(items.count) reviewed"
        }
        return "\(currentIndex + 1) of \(items.count)"
    }

    /// Finished reviewing a non-empty list.
    var isFinished: Bool {
        !isLoading && folderURL != nil && !items.isEmpty && currentIndex >= items.count
    }

    /// Folder loaded but nothing to review.
    var isEmptyFolder: Bool {
        !isLoading && folderURL != nil && items.isEmpty
    }

    var canUndo: Bool { !history.isEmpty }

    // MARK: - Real user paths (not the app sandbox container)

    /// Sandboxed apps report a fake home under Containers/. Use the real login home instead.
    nonisolated static var realHomeDirectory: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        // Fallback: strip the Containers path if present
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.path
        if let range = path.range(of: "/Library/Containers/") {
            return URL(fileURLWithPath: String(path[..<range.lowerBound]), isDirectory: true)
        }
        return home
    }

    nonisolated static var realDownloadsDirectory: URL {
        realHomeDirectory.appendingPathComponent("Downloads", isDirectory: true)
    }

    // MARK: - Folder loading

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Review Folder"
        panel.message = "Pick a folder to swipe through (for example Downloads)."
        panel.directoryURL = Self.realDownloadsDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        // User-selected folders need security-scoped access under App Sandbox.
        let accessed = url.startAccessingSecurityScopedResource()
        loadFolder(url, securityScoped: accessed ? url : nil)
    }

    func loadDownloads() {
        let downloads = Self.realDownloadsDirectory
        guard fileManager.fileExists(atPath: downloads.path) else {
            errorMessage = "Could not find your Downloads folder at \(downloads.path)"
            return
        }
        // Downloads entitlement allows direct access; still try security scope if offered.
        let accessed = downloads.startAccessingSecurityScopedResource()
        loadFolder(downloads, securityScoped: accessed ? downloads : nil)
    }

    func loadFolder(_ url: URL, securityScoped: URL? = nil, preserveSecurityScope: Bool = false) {
        if !preserveSecurityScope {
            // Drop previous folder access
            if let previous = securityScopedFolder {
                previous.stopAccessingSecurityScopedResource()
                securityScopedFolder = nil
            }
            if let securityScoped {
                securityScopedFolder = securityScoped
            }
        }

        folderURL = url
        errorMessage = nil
        keptCount = 0
        deletedCount = 0
        history.removeAll()
        isLoading = true
        items = []
        currentIndex = 0

        let sort = sortMode
        let folderPath = url.path

        Task.detached(priority: .userInitiated) {
            // Verify we can actually list the folder
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDir)
            guard exists, isDir.boolValue else {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "That folder does not exist or is not readable:\n\(folderPath)"
                }
                return
            }

            do {
                let scanned = try Self.scan(folder: url, sortMode: sort)
                await MainActor.run {
                    self.items = scanned
                    self.currentIndex = 0
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.items = []
                    self.currentIndex = 0
                    self.isLoading = false
                    self.errorMessage = "Could not read that folder. Try Choose Folder… and pick it again.\n\n\(error.localizedDescription)"
                }
            }
        }
    }

    func reload() {
        guard let folderURL else { return }
        loadFolder(folderURL, preserveSecurityScope: true)
    }

    /// Leave this folder and go back to the start screen (pick Downloads or another folder).
    /// Does not delete or move anything — just ends this review pass.
    func done() {
        if let previous = securityScopedFolder {
            previous.stopAccessingSecurityScopedResource()
            securityScopedFolder = nil
        }
        folderURL = nil
        items = []
        currentIndex = 0
        keptCount = 0
        deletedCount = 0
        history.removeAll()
        isLoading = false
        errorMessage = nil
    }

    /// Jump to the “all done” summary without reviewing the rest.
    func finishEarly() {
        guard folderURL != nil, !items.isEmpty else {
            done()
            return
        }
        currentIndex = items.count
    }

    // MARK: - Actions

    /// Leave the file exactly where it is on disk (no move, no rename, no date change).
    /// Only advances to the next card in this review pass.
    func keepCurrent() {
        guard let item = currentItem else { return }
        pushHistory(HistoryEntry(item: item, action: .kept, indexBefore: currentIndex))
        keptCount += 1
        advance()
    }

    func deleteCurrent() {
        guard let item = currentItem else { return }
        let indexBefore = currentIndex

        // File may already be gone (deleted in Finder mid-review)
        guard fileManager.fileExists(atPath: item.url.path) else {
            items.remove(at: currentIndex)
            if currentIndex > items.count {
                currentIndex = items.count
            }
            return
        }

        do {
            var resultingURL: NSURL?
            try fileManager.trashItem(at: item.url, resultingItemURL: &resultingURL)
            let trashURL = resultingURL as URL?
            pushHistory(
                HistoryEntry(
                    item: item,
                    action: .deleted(originalURL: item.url, trashURL: trashURL),
                    indexBefore: indexBefore
                )
            )
            deletedCount += 1
            items.remove(at: currentIndex)
            // Stay on the same index so the next item slides into place
            if currentIndex > items.count {
                currentIndex = items.count
            }
        } catch {
            errorMessage = "Could not move “\(item.name)” to Trash: \(error.localizedDescription)"
        }
    }

    private func pushHistory(_ entry: HistoryEntry) {
        history.append(entry)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
    }

    func undoLast() {
        guard let entry = history.popLast() else { return }

        switch entry.action {
        case .kept:
            keptCount = max(0, keptCount - 1)
            currentIndex = min(entry.indexBefore, items.count)
        case .deleted(let originalURL, let trashURL):
            deletedCount = max(0, deletedCount - 1)
            if let trashURL {
                do {
                    // Prefer restore from Trash URL if available
                    if fileManager.fileExists(atPath: trashURL.path) {
                        try fileManager.moveItem(at: trashURL, to: originalURL)
                    }
                    if let restored = FileItem.from(url: originalURL) {
                        let insertAt = min(entry.indexBefore, items.count)
                        items.insert(restored, at: insertAt)
                        currentIndex = insertAt
                    }
                } catch {
                    errorMessage = "Undo failed: \(error.localizedDescription)"
                }
            } else if let restored = FileItem.from(url: originalURL) {
                let insertAt = min(entry.indexBefore, items.count)
                items.insert(restored, at: insertAt)
                currentIndex = insertAt
            }
        }
    }

    func revealCurrentInFinder() {
        guard let item = currentItem else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func quickLookCurrent() {
        guard let item = currentItem else { return }
        QuickLookHelper.shared.preview(urls: [item.url])
    }

    func openCurrentWithDefaultApp() {
        guard let item = currentItem else { return }
        NSWorkspace.shared.open(item.url)
    }

    // MARK: - Private

    private func advance() {
        if currentIndex < items.count {
            currentIndex += 1
        }
    }

    /// Only the items sitting in this folder (not buried deeper).
    /// Folders stay as one card — look inside on the card, then keep or trash the whole folder.
    nonisolated private static func scan(
        folder: URL,
        sortMode: SortMode
    ) throws -> [FileItem] {
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .fileSizeKey,
                .addedToDirectoryDateKey,
                .creationDateKey,
                .contentModificationDateKey,
                .nameKey,
                .contentTypeKey,
                .isHiddenKey,
            ],
            options: [.skipsHiddenFiles]
        )

        var items = urls.compactMap { FileItem.from(url: $0) }

        switch sortMode {
        case .newestAdded:
            // Same idea as Finder → Downloads → sort by Date Added
            items.sort { $0.dateAdded > $1.dateAdded }
        case .oldestAdded:
            items.sort { $0.dateAdded < $1.dateAdded }
        case .largestFirst:
            items.sort { $0.size > $1.size }
        case .nameAZ:
            items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return items
    }
}

// MARK: - Quick Look

@MainActor
final class QuickLookHelper: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookHelper()
    private var urls: [URL] = []

    func preview(urls: [URL]) {
        self.urls = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }
}
