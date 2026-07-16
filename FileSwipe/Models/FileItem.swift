import Foundation
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    let size: Int64
    /// When it landed in this folder (Finder “Date Added”). Prefer this for ordering Downloads.
    let dateAdded: Date
    /// Last modified — can change if an app rewrites the file; not the same as Date Added.
    let modified: Date
    let isDirectory: Bool
    let utType: UTType?

    var path: String { url.path }

    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Prefer Date Added (matches Downloads in Finder).
    var dateAddedString: String {
        dateAdded.formatted(date: .abbreviated, time: .shortened)
    }

    var modifiedString: String {
        modified.formatted(date: .abbreviated, time: .shortened)
    }

    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    var kindLabel: String {
        if isDirectory { return "Folder" }
        if let utType {
            return utType.localizedDescription?.capitalized ?? fileExtension.uppercased()
        }
        return fileExtension.isEmpty ? "File" : fileExtension.uppercased()
    }

    var previewKind: PreviewKind {
        if isDirectory { return .folder }
        guard let utType else { return .generic }

        if utType.conforms(to: .image) { return .image }
        if utType.conforms(to: .pdf) { return .pdf }
        if utType.conforms(to: .movie) || utType.conforms(to: .video) { return .video }
        if utType.conforms(to: .audio) { return .audio }
        if utType.conforms(to: .text)
            || utType.conforms(to: .sourceCode)
            || utType.conforms(to: .json)
            || utType.conforms(to: .xml)
            || ["md", "txt", "csv", "log", "json", "yml", "yaml", "swift", "js", "ts", "py", "html", "css"].contains(fileExtension)
        {
            return .text
        }
        return .generic
    }

    enum PreviewKind {
        case image, pdf, text, video, audio, folder, generic
    }

    static func from(url: URL) -> FileItem? {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .fileSizeKey,
                .addedToDirectoryDateKey,
                .creationDateKey,
                .contentModificationDateKey,
                .nameKey,
                .contentTypeKey,
                .isHiddenKey,
            ])
        } catch {
            return nil
        }

        if values.isHidden == true { return nil }

        let isDirectory = values.isDirectory == true
        let isFile = values.isRegularFile == true
        guard isDirectory || isFile else { return nil }

        let modified = values.contentModificationDate ?? .distantPast
        // Same idea as Finder’s “Date Added” column in Downloads.
        let dateAdded = values.addedToDirectoryDate
            ?? values.creationDate
            ?? modified

        return FileItem(
            id: url,
            url: url,
            name: values.name ?? url.lastPathComponent,
            size: Int64(values.fileSize ?? 0),
            dateAdded: dateAdded,
            modified: modified,
            isDirectory: isDirectory,
            utType: values.contentType
        )
    }
}
