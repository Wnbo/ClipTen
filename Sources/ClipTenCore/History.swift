import Foundation

public enum ClipContent: Equatable, Sendable, Codable {
    case text(String)
    case image(Data, type: String)
}

public struct ClipRecord: Identifiable, Sendable, Codable {
    public let id: UUID
    public let content: ClipContent
    public let copiedAt: Date
    public internal(set) var isLocked: Bool

    public init(id: UUID, content: ClipContent, copiedAt: Date, isLocked: Bool = false) {
        self.id = id
        self.content = content
        self.copiedAt = copiedAt
        self.isLocked = isLocked
    }

    private enum CodingKeys: String, CodingKey { case id, content, copiedAt, isLocked }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        content = try values.decode(ClipContent.self, forKey: .content)
        copiedAt = try values.decode(Date.self, forKey: .copiedAt)
        isLocked = try values.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
    }
}

public struct ClipHistory: Sendable {
    public static let lockLimit = 7
    public var lockedCount: Int { records.filter(\.isLocked).count }
    public private(set) var records: [ClipRecord] = []
    public init() {}

    public init(records: [ClipRecord]) {
        var seen: [ClipContent] = []
        self.records = records.filter {
            guard !seen.contains($0.content) else { return false }
            seen.append($0.content)
            return true
        }.prefix(10).map { $0 }
        var locks = 0
        for index in self.records.indices where self.records[index].isLocked {
            locks += 1
            if locks > Self.lockLimit { self.records[index].isLocked = false }
        }
    }

    public mutating func insert(_ content: ClipContent, at date: Date = Date()) {
        // Recopying preserves identity and the lock, while updating recency.
        let previous = records.first { $0.content == content }
        records.removeAll { $0.content == content }
        records.insert(ClipRecord(id: previous?.id ?? UUID(), content: content, copiedAt: date,
                                  isLocked: previous?.isLocked ?? false), at: 0)
        while records.count > 10, let index = records.lastIndex(where: { !$0.isLocked }) {
            records.remove(at: index)
        }
    }

    @discardableResult
    public mutating func toggleLock(id: UUID) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == id }),
              records[index].isLocked || lockedCount < Self.lockLimit else { return false }
        records[index].isLocked.toggle()
        return true
    }

    public mutating func clear() { records.removeAll { !$0.isLocked } }
    public mutating func remove(id: UUID) { records.removeAll { $0.id == id && !$0.isLocked } }

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
