import AppKit
import AVFoundation
import AVKit
import PDFKit
import QuickLookThumbnailing
import SwiftUI

struct FilePreviewView: View {
    let item: FileItem

    var body: some View {
        Group {
            switch item.previewKind {
            case .image:
                ImagePreview(url: item.url)
            case .pdf:
                PDFPreview(url: item.url)
            case .text:
                TextPreview(url: item.url)
            case .video:
                MediaPlayerPreview(url: item.url, kind: .video)
            case .audio:
                MediaPlayerPreview(url: item.url, kind: .audio)
            case .folder:
                FolderPreview(root: item)
            case .generic:
                GenericPreview(item: item)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Image

private struct ImagePreview: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
            } else {
                ProgressView("Loading image…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            image = NSImage(contentsOf: url)
        }
    }
}

// MARK: - PDF
// PDFView + flexible SwiftUI layout can recurse forever and crash.
// Always size it from GeometryReader and report a concrete sizeThatFits.

private struct PDFPreview: View {
    let url: URL

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let h = max(geo.size.height, 1)
            PDFKitRepresentable(url: url, size: CGSize(width: w, height: h))
                .frame(width: w, height: h)
        }
        .padding(8)
    }
}

private struct PDFKitRepresentable: NSViewRepresentable {
    let url: URL
    let size: CGSize

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }

    // Stop SwiftUI from asking PDFView for an unbounded ideal size (crash source).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PDFView, context: Context) -> CGSize? {
        let width = proposal.width ?? size.width
        let height = proposal.height ?? size.height
        return CGSize(width: max(width, 1), height: max(height, 1))
    }
}

// MARK: - Text

private struct TextPreview: View {
    let url: URL
    @State private var text: String = ""
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                PlaceholderPreview(
                    systemImage: "doc.text",
                    title: url.lastPathComponent,
                    subtitle: "Could not read this file as text"
                )
            } else if text.isEmpty {
                ProgressView("Reading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            failed = false
            text = ""
            do {
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                let limit = min(data.count, 200_000)
                let slice = data.prefix(limit)
                if let string = String(data: slice, encoding: .utf8)
                    ?? String(data: slice, encoding: .isoLatin1)
                {
                    text = string + (data.count > limit ? "\n\n… (truncated for preview)" : "")
                } else {
                    failed = true
                }
            } catch {
                failed = true
            }
        }
    }
}

// MARK: - Folder contents
// Keep this layout boring and fully SwiftUI-owned (no List / HSplitView / nested PDFView).
// Nested PDF uses a thumbnail + Quick Look to avoid the PDF layout crash inside cards.

private struct FolderPreview: View {
    let root: FileItem

    @State private var path: [URL] = []
    @State private var children: [FileItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selected: FileItem?
    @State private var totalBytes: Int64 = 0
    @State private var trashedInsideCount = 0
    @State private var actionError: String?

    private var currentFolder: URL {
        path.last ?? root.url
    }

    private var canGoUp: Bool {
        !path.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            folderHeader
            Divider()
            contentBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: root.url) {
            path = []
            selected = nil
            trashedInsideCount = 0
            actionError = nil
            await loadChildren(of: root.url)
        }
        .onChange(of: path) { _, _ in
            selected = nil
            actionError = nil
            Task { await loadChildren(of: currentFolder) }
        }
        .alert("Couldn’t delete", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        if isLoading {
            ProgressView("Loading contents…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            PlaceholderPreview(
                systemImage: "exclamationmark.triangle",
                title: "Couldn’t open folder",
                subtitle: loadError
            )
        } else if children.isEmpty {
            PlaceholderPreview(
                systemImage: "folder",
                title: trashedInsideCount > 0 ? "Folder is empty now" : "Empty folder",
                subtitle: trashedInsideCount > 0
                    ? "You removed \(trashedInsideCount) item\(trashedInsideCount == 1 ? "" : "s") from inside. Swipe right to keep this empty folder, or left to trash it too."
                    : "Nothing to show inside"
            )
        } else {
            GeometryReader { geo in
                let listWidth = min(280, max(200, geo.size.width * 0.38))
                HStack(spacing: 0) {
                    contentsList
                        .frame(width: listWidth)
                        .frame(height: geo.size.height)

                    Divider()

                    detailPane
                        .frame(width: max(geo.size.width - listWidth - 1, 1))
                        .frame(height: geo.size.height)
                }
            }
        }
    }

    private var folderHeader: some View {
        HStack(spacing: 10) {
            if canGoUp {
                Button {
                    path.removeLast()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
            }

            Image(systemName: "folder.fill")
                .foregroundStyle(.yellow.opacity(0.9))

            VStack(alignment: .leading, spacing: 1) {
                Text(currentFolder.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var summaryText: String {
        let count = children.count
        let size = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        var parts = ["\(count) item\(count == 1 ? "" : "s")", size]
        if trashedInsideCount > 0 {
            parts.append("\(trashedInsideCount) deleted from inside")
        }
        parts.append("Swipe = whole folder")
        return parts.joined(separator: " · ")
    }

    private var contentsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(children) { child in
                    FolderRow(item: child, isSelected: selected?.id == child.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selected = child
                        }
                        .onTapGesture(count: 2) {
                            if child.isDirectory {
                                path.append(child.url)
                            } else {
                                selected = child
                            }
                        }
                        .contextMenu {
                            if child.isDirectory {
                                Button("Open") { path.append(child.url) }
                            }
                            Button("Move to Trash", role: .destructive) {
                                trashItem(child)
                            }
                        }
                }
            }
            .padding(.vertical, 4)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selected {
            VStack(spacing: 0) {
                SafeInnerPreview(item: selected) {
                    if selected.isDirectory {
                        path.append(selected.url)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selected.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("Only this item — not the whole folder")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(role: .destructive) {
                        trashItem(selected)
                    } label: {
                        Label("Trash this", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "eye")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Click something to look at it")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Use “Trash this” to remove just that item.\nSwipe left only if you want the whole folder gone.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func trashItem(_ item: FileItem) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            trashedInsideCount += 1

            if let index = children.firstIndex(of: item) {
                children.remove(at: index)
                totalBytes = children.reduce(0) { $0 + $1.size }

                if selected?.id == item.id {
                    if children.indices.contains(index) {
                        selected = children[index]
                    } else if children.indices.contains(index - 1) {
                        selected = children[index - 1]
                    } else {
                        selected = children.first
                    }
                }
            } else {
                children.removeAll { $0.id == item.id }
                if selected?.id == item.id {
                    selected = children.first
                }
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func loadChildren(of folder: URL) async {
        isLoading = true
        loadError = nil
        let result = await Task.detached(priority: .userInitiated) {
            Self.scanFolder(folder)
        }.value
        children = result.items
        totalBytes = result.totalBytes
        loadError = result.error
        isLoading = false
        if selected == nil || !(children.contains { $0.id == selected?.id }) {
            selected = children.first(where: { !$0.isDirectory }) ?? children.first
        }
    }

    nonisolated private static func scanFolder(_ folder: URL) -> (items: [FileItem], totalBytes: Int64, error: String?) {
        let fm = FileManager.default
        do {
            let urls = try fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isDirectoryKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                    .nameKey,
                    .contentTypeKey,
                    .isHiddenKey,
                ],
                options: [.skipsHiddenFiles]
            )
            var items = urls.compactMap { FileItem.from(url: $0) }
            items.sort {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory && !$1.isDirectory
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            let total = items.reduce(Int64(0)) { $0 + $1.size }
            return (items, total, nil)
        } catch {
            return ([], 0, error.localizedDescription)
        }
    }
}

/// Previews used *inside* a folder card — avoid nesting PDFView (layout crash).
private struct SafeInnerPreview: View {
    let item: FileItem
    let onOpenFolder: () -> Void

    var body: some View {
        Group {
            if item.isDirectory {
                VStack(spacing: 14) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.yellow.opacity(0.9))
                    Text(item.name)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Open to look inside, or trash just this folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open folder", action: onOpenFolder)
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                switch item.previewKind {
                case .image:
                    ImagePreview(url: item.url)
                case .text:
                    TextPreview(url: item.url)
                case .video:
                    MediaPlayerPreview(url: item.url, kind: .video)
                case .audio:
                    MediaPlayerPreview(url: item.url, kind: .audio)
                case .pdf, .generic, .folder:
                    // Thumbnail-only for PDF (full PDFView nesting can crash layout)
                    ThumbnailDetail(item: item)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(item.id)
    }
}

private struct ThumbnailDetail: View {
    let item: FileItem
    @State private var thumbnail: NSImage?
    @State private var icon: NSImage?

    var body: some View {
        VStack(spacing: 14) {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 16)
            } else if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
            } else {
                ProgressView()
            }

            Text(item.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("\(item.kindLabel) · \(item.sizeString)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if item.previewKind == .pdf {
                Text("Full PDF preview is on the main card — here you get a page preview")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.url) {
            icon = NSWorkspace.shared.icon(forFile: item.url.path)
            icon?.size = NSSize(width: 128, height: 128)
            thumbnail = await ThumbnailLoader.load(url: item.url, size: CGSize(width: 640, height: 400))
        }
    }
}

private struct FolderRow: View {
    let item: FileItem
    var isSelected: Bool
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: item.isDirectory ? "folder.fill" : iconName)
                        .foregroundStyle(item.isDirectory ? Color.yellow.opacity(0.9) : Color.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.isDirectory ? "Folder" : "\(item.kindLabel) · \(item.sizeString)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if item.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .task(id: item.url) {
            guard !item.isDirectory else { return }
            if item.previewKind == .image || item.previewKind == .video || item.previewKind == .pdf {
                thumbnail = await ThumbnailLoader.load(url: item.url, size: CGSize(width: 56, height: 56))
            }
        }
    }

    private var iconName: String {
        switch item.previewKind {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .text: return "doc.text"
        case .video: return "film"
        case .audio: return "waveform"
        default: return "doc"
        }
    }
}

// MARK: - Video / audio (thumbnail first, play on demand)

private enum MediaKind {
    case video
    case audio

    var playLabel: String {
        switch self {
        case .video: return "Play video"
        case .audio: return "Play audio"
        }
    }

    var iconName: String {
        switch self {
        case .video: return "film"
        case .audio: return "waveform"
        }
    }
}

/// Starts as a still preview. Player only mounts after the user taps Play
/// (avoids layout crashes from embedding AVPlayerView during card transitions).
private struct MediaPlayerPreview: View {
    let url: URL
    let kind: MediaKind

    @State private var wantsPlayer = false
    @State private var thumbnail: NSImage?
    @StateObject private var model = MediaPlayerModel()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if wantsPlayer {
                    SafeMediaPlayerHost(model: model, kind: kind, url: url) {
                        // Close player → back to thumbnail
                        model.tearDown()
                        wantsPlayer = false
                    }
                } else {
                    mediaPoster
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            HStack(spacing: 10) {
                Image(systemName: kind.iconName)
                    .foregroundStyle(.secondary)
                Text(wantsPlayer
                     ? "Drag the bar to scrub · Close to go back to the still"
                     : "Still preview — press Play only if you want to watch/listen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            // Always reset to poster when the card’s file changes
            wantsPlayer = false
            model.tearDown()
            thumbnail = nil
            thumbnail = await ThumbnailLoader.load(url: url, size: CGSize(width: 960, height: 540))
        }
        .onDisappear {
            model.tearDown()
            wantsPlayer = false
        }
    }

    private var mediaPoster: some View {
        ZStack {
            Color.black.opacity(kind == .video ? 0.92 : 0.06)

            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(20)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: kind.iconName)
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Big play control — only starts the heavy player when tapped
            Button {
                wantsPlayer = true
            } label: {
                Label(kind.playLabel, systemImage: "play.fill")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap poster also starts playback
            wantsPlayer = true
        }
    }
}

/// Only creates AVPlayerView when we have a finite, non-zero size (prevents NaN frame crash).
private struct SafeMediaPlayerHost: View {
    @ObservedObject var model: MediaPlayerModel
    let kind: MediaKind
    let url: URL
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geo in
            let size = Self.safeSize(from: geo.size)

            ZStack {
                Color.black.opacity(kind == .video ? 1 : 0.06)

                if let player = model.player, let size {
                    AVPlayerViewRepresentable(player: player)
                        .frame(width: size.width, height: size.height)
                } else if model.failed {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("Couldn’t play this file")
                            .foregroundStyle(.secondary)
                        Button("Back to still", action: onClose)
                    }
                } else {
                    ProgressView(kind == .audio ? "Loading audio…" : "Loading video…")
                }

                VStack {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Label("Close player", systemImage: "xmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(10)
                        }
                        .buttonStyle(.plain)
                        .help("Back to thumbnail")
                    }
                    Spacer()
                }
            }
            .frame(width: size?.width ?? max(geo.size.width, 0),
                   height: size?.height ?? max(geo.size.height, 0))
            .onAppear {
                if size != nil {
                    model.load(url: url)
                }
            }
            .onChange(of: geo.size) { _, newSize in
                if Self.safeSize(from: newSize) != nil, model.player == nil, !model.failed {
                    model.load(url: url)
                }
            }
        }
    }

    /// Reject 0 / infinite / NaN sizes that crash AppKit (“x is NaN”).
    private static func safeSize(from size: CGSize) -> CGSize? {
        let w = size.width
        let h = size.height
        guard w.isFinite, h.isFinite, w >= 32, h >= 32 else { return nil }
        return CGSize(width: w, height: h)
    }
}

@MainActor
private final class MediaPlayerModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var failed = false
    private var currentURL: URL?

    /// Load and start playing as soon as the file is ready (one tap on Play).
    func load(url: URL) {
        if currentURL == url, let player {
            player.play()
            return
        }
        tearDown()
        currentURL = url
        failed = false

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.actionAtItemEnd = .pause
        player = newPlayer

        Task { [weak self] in
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    // User already pressed Play on the poster — start immediately.
                    self.player?.play()
                    return
                case .failed:
                    self.failed = true
                    self.player = nil
                    return
                case .unknown:
                    continue
                @unknown default:
                    continue
                }
            }
        }
    }

    func tearDown() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        currentURL = nil
        failed = false
    }
}

/// Native macOS player chrome: play/pause, volume, and scrubber.
/// Wrapped in a plain NSView so SwiftUI never drives AVPlayerView with a NaN frame.
private struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    final class Container: NSView {
        let playerView = AVPlayerView()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            playerView.controlsStyle = .inline
            playerView.showsFullScreenToggleButton = true
            playerView.showsTimecodes = true
            playerView.videoGravity = .resizeAspect
            playerView.allowsPictureInPicturePlayback = false
            playerView.autoresizingMask = [.width, .height]
            addSubview(playerView)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            // Never set a NaN/zero frame on AVPlayerView
            let b = bounds
            guard b.width.isFinite, b.height.isFinite, b.width > 1, b.height > 1 else {
                playerView.isHidden = true
                return
            }
            playerView.isHidden = false
            playerView.frame = b.integral
        }
    }

    func makeNSView(context: Context) -> Container {
        let container = Container(frame: .zero)
        container.playerView.player = player
        return container
    }

    func updateNSView(_ nsView: Container, context: Context) {
        if nsView.playerView.player !== player {
            nsView.playerView.player = player
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Container, context: Context) -> CGSize? {
        let width = proposal.width ?? 640
        let height = proposal.height ?? 360
        guard width.isFinite, height.isFinite else {
            return CGSize(width: 640, height: 360)
        }
        return CGSize(width: max(width, 32), height: max(height, 32))
    }

    static func dismantleNSView(_ nsView: Container, coordinator: ()) {
        nsView.playerView.player?.pause()
        nsView.playerView.player = nil
    }
}

private struct GenericPreview: View {
    let item: FileItem
    @State private var thumbnail: NSImage?
    @State private var icon: NSImage?

    var body: some View {
        VStack(spacing: 16) {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 24)
            } else if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.secondary)
            }

            Text(item.name)
                .font(.title3.weight(.semibold))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("\(item.kindLabel) · \(item.sizeString)")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.url) {
            icon = NSWorkspace.shared.icon(forFile: item.url.path)
            icon?.size = NSSize(width: 128, height: 128)
            thumbnail = await ThumbnailLoader.load(url: item.url, size: CGSize(width: 640, height: 400))
        }
    }
}

private struct PlaceholderPreview: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

enum ThumbnailLoader {
    static func load(url: URL, size: CGSize) async -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                continuation.resume(returning: rep?.nsImage)
            }
        }
    }
}
