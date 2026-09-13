import Foundation

public enum ClipContent: Equatable, Sendable, Codable {
    case text(String)
    case image(Data, type: String)
}

public struct ClipRecord: Identifiable, Sendable, Codable {
    public let id: UUID
    public let content: ClipContent
    public let copiedAt: Date
}

public struct ClipHistory: Sendable {
    public private(set) var records: [ClipRecord] = []
    public init() {}

    public init(records: [ClipRecord]) {
        var seen: [ClipContent] = []
        self.records = records.filter {
            guard !seen.contains($0.content) else { return false }
            seen.append($0.content)
            return true
        }.prefix(10).map { $0 }
    }

    public mutating func insert(_ content: ClipContent, at date: Date = Date()) {
        // Keep useful distinct entries; copying an older entry moves it to the top.
        records.removeAll { $0.content == content }
        records.insert(ClipRecord(id: UUID(), content: content, copiedAt: date), at: 0)
        if records.count > 10 { records.removeLast(records.count - 10) }
    }

    public mutating func clear() { records.removeAll() }
    public mutating func remove(id: UUID) { records.removeAll { $0.id == id } }

    public func matchingRecordID(for content: ClipContent?) -> UUID? {
        guard let content else { return nil }
        return records.first { $0.content == content }?.id
    }
}

public enum CapturePolicy {
    public static let maxTextBytes = 5 * 1024 * 1024
    public static let maxImageBytes = 25 * 1024 * 1024

    public static func containsFile(_ types: [String]) -> Bool {
        let fileTypes: Set<String> = [
            "public.file-url", "NSFilenamesPboardType", "NSFilesPromisePboardType",
            "com.apple.pasteboard.promised-file-url", "com.apple.pasteboard.promised-file-content",
            "com.apple.pasteboard.promised-file-content-type"
        ]
        return types.contains { fileTypes.contains($0) }
    }

    public static func isSensitive(_ types: [String]) -> Bool {
        types.contains("org.nspasteboard.ConcealedType")
            || types.contains("org.nspasteboard.TransientType")
    }
}
