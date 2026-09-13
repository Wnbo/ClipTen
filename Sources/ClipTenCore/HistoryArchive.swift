import Foundation

/// Serializes disk I/O away from the UI actor. The one archive contains original
/// image bytes as binary plist data, so deletion cannot leave orphan image files.
public actor HistoryArchive {
    public let fileURL: URL

    private struct Document: Codable {
        let version: Int
        let records: [ClipRecord]
    }

    public enum ArchiveError: LocalizedError {
        case invalidArchive
        public var errorDescription: String? { "历史文件格式无效或内容超出限制。" }
    }

    public init(fileURL: URL) { self.fileURL = fileURL }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipTen", isDirectory: true)
            .appendingPathComponent("history.plist")
    }

    public func load() throws -> ClipHistory? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= 260 * 1024 * 1024 else {
            throw ArchiveError.invalidArchive
        }
        let document = try PropertyListDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
        guard document.version == 1, document.records.count <= 10,
              Set(document.records.map(\.id)).count == document.records.count,
              document.records.allSatisfy({ Self.isValid($0.content) }) else {
            throw ArchiveError.invalidArchive
        }
        return ClipHistory(records: document.records)
    }

    public func save(_ history: ClipHistory) throws {
        guard history.records.allSatisfy({ Self.isValid($0.content) }) else { throw ArchiveError.invalidArchive }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(Document(version: 1, records: history.records))
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func remove() throws {
        // Only remove our archive, never the parent directory or unrelated files.
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func isValid(_ content: ClipContent) -> Bool {
        switch content {
        case .text(let text): !text.isEmpty && text.utf8.count <= CapturePolicy.maxTextBytes
        case .image(let data, let type):
            !data.isEmpty && data.count <= CapturePolicy.maxImageBytes && ["public.png", "public.tiff"].contains(type)
        }
    }
}
