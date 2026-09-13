import AppKit
import ClipTenCore
import ImageIO
import SwiftUI

@MainActor
final class ClipboardStore: ObservableObject {
    enum ClipboardAccess { case allowed, ask, denied }

    enum PendingDeletion {
        case all
        case current(ClipRecord)
    }

    @Published private(set) var pendingDeletion: PendingDeletion?
    @Published private(set) var confirmsClipboardClear: Bool
    @Published private(set) var history = ClipHistory()
    @Published private(set) var currentRecordID: UUID?
    @Published private(set) var notice: String?
    @Published private(set) var permissionNotice: String?
    @Published private(set) var savesToDisk: Bool
    @Published private(set) var diskError: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isChangingStorage = false
    private let preferences: UserDefaults
    private let archive: HistoryArchive
    private var persistenceTask: Task<Void, Never>?
    private var persistenceRevision = 0
    private var isTerminating = false
    private var startupTask: Task<Void, Never>?
    private let pasteboard: NSPasteboard
    private var lastChange: Int
    private var timer: Timer?
    private var thumbnails: [UUID: NSImage] = [:]
    private var wasDenied = false
    private var nextPermissionCheck: TimeInterval = 0
    private let uptime: () -> TimeInterval
    private let readAccess: () -> ClipboardAccess

    init(pasteboard: NSPasteboard = .general, preferences: UserDefaults = .standard,
         archive: HistoryArchive = HistoryArchive(fileURL: HistoryArchive.defaultURL),
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         readAccess: (() -> ClipboardAccess)? = nil) {
        self.pasteboard = pasteboard
        self.preferences = preferences
        self.archive = archive
        self.uptime = uptime
        self.readAccess = readAccess ?? {
            if #available(macOS 15.4, *) {
                switch pasteboard.accessBehavior {
                case .alwaysDeny: return .denied
                case .ask: return .ask
                default: return .allowed
                }
            }
            return .allowed
        }
        confirmsClipboardClear = preferences.object(forKey: "confirmClipboardClear") as? Bool ?? true
        savesToDisk = preferences.bool(forKey: "saveHistoryToDisk")
        lastChange = pasteboard.changeCount - 1
    }

    func start() {
        guard startupTask == nil else { return }
        isLoading = true
        let startingChange = pasteboard.changeCount
        startupTask = Task { [weak self] in
            guard let self else { return }
            await self.loadSavedHistory()
            // A stored archive (even an empty one) is authoritative on launch.
            // Do not resurrect a deleted entry from the unchanged system clipboard.
            let shouldRecord = !(self.savesToDisk && self.didLoadArchive && self.pasteboard.changeCount == startingChange)
            self.isLoading = false
            self.poll(recordChanges: shouldRecord)
            self.startTimer()
        }
    }

    private var didLoadArchive = false

    func loadSavedHistory() async {
        do {
            if savesToDisk {
                if let saved = try await archive.load() {
                    history = saved
                    didLoadArchive = true
                }
            } else {
                // Clean up an interrupted opt-in which never committed its preference.
                try await archive.remove()
            }
            diskError = nil
        } catch {
            diskError = "读取本地历史失败：\(error.localizedDescription)"
        }
    }

    private func startTimer() {
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        if let timer {
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func poll(recordChanges: Bool = true, refreshPermissions: Bool = false) {
        guard !isLoading, !isTerminating, !isChangingStorage else { return }
        let count = pasteboard.changeCount
        let now = uptime()
        // Keep the idle path to a change counter and a monotonic deadline.
        // Changes and explicit user interaction bypass the five-second cache.
        if refreshPermissions || count != lastChange || now >= nextPermissionCheck {
            nextPermissionCheck = now + 5
            let access = readAccess()
            let message: String?
            switch access {
            case .denied:
                message = "剪贴板读取被系统禁止，请在系统设置中允许拾贴访问。"
            case .ask:
                message = "如需自动记录，请在系统设置的剪贴板访问选项中允许拾贴持续读取。"
            case .allowed:
                message = nil
            }
            if permissionNotice != message { permissionNotice = message }
            if access == .denied {
                if currentRecordID != nil { currentRecordID = nil }
                // Acknowledge denied changes so they do not trigger repeated checks.
                lastChange = count
                wasDenied = true
                return
            }
            if wasDenied {
                lastChange = count - 1
                wasDenied = false
            }
        }
        guard !wasDenied else { return }
        guard count != lastChange else { return }
        // Acknowledge before reading, including unsupported items.
        lastChange = count
        // Unsupported, empty, oversized or unreadable contents must also clear
        // the marker, even though they do not create a new history entry.
        if currentRecordID != nil { currentRecordID = nil }
        if notice != nil { notice = nil }
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard !CapturePolicy.containsFile(types), !CapturePolicy.isSensitive(types) else { return }
        guard let items = pasteboard.pasteboardItems, items.count == 1, let item = items.first else { return }

        var captured: ClipContent?
        // Images can also carry a URL or alt text; prefer the image representation.
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = item.data(forType: type) {
                guard data.count <= CapturePolicy.maxImageBytes else {
                    notice = "已跳过超过 25 MB 的图片。"
                    return
                }
                guard Self.makeThumbnail(data) != nil else {
                    notice = "这张图片无法读取，已跳过。"
                    return
                }
                captured = .image(data, type: type.rawValue)
                break
            }
        }
        if captured == nil, let text = item.string(forType: .string), !text.isEmpty {
            guard text.utf8.count <= CapturePolicy.maxTextBytes else {
                notice = "已跳过超过 5 MB 的文字。"
                return
            }
            captured = .text(text)
        }
        // A source app may change the clipboard while rendering its promised data.
        guard pasteboard.changeCount == count, let captured else { return }
        if recordChanges { history.insert(captured) }
        let matchingID = history.matchingRecordID(for: captured)
        if currentRecordID != matchingID { currentRecordID = matchingID }
        let retained = Set(history.records.map(\.id))
        thumbnails = thumbnails.filter { retained.contains($0.key) }
        if recordChanges { scheduleSave() }
    }

    @discardableResult
    func restore(_ record: ClipRecord) -> Bool {
        let item = NSPasteboardItem()
        switch record.content {
        case .text(let text): item.setString(text, forType: .string)
        case .image(let data, let type): item.setData(data, forType: .init(type))
        }
        pasteboard.clearContents()
        let success = pasteboard.writeObjects([item])
        if currentRecordID != nil { currentRecordID = nil }
        lastChange = pasteboard.changeCount - (success ? 1 : 0)
        // Read back the actual clipboard without adding/moving a history row.
        // This also handles another app replacing our write immediately.
        if success { poll(recordChanges: false) }
        notice = success ? nil : "写入剪贴板失败，请重试。"
        return success
    }

    func setConfirmsClipboardClear(_ enabled: Bool) {
        confirmsClipboardClear = enabled
        preferences.set(enabled, forKey: "confirmClipboardClear")
    }

    func requestClear() {
        guard !isLoading, !isTerminating, !isChangingStorage else { return }
        if confirmsClipboardClear { pendingDeletion = .all }
        else { clear() }
    }

    func requestRemove(_ record: ClipRecord) {
        guard !isLoading, !isTerminating, !isChangingStorage else { return }
        if confirmsClipboardClear && currentRecordID == record.id {
            pendingDeletion = .current(record)
        } else {
            remove(record)
        }
    }

    func cancelDeletion() { pendingDeletion = nil }

    func confirmDeletion() {
        guard let pendingDeletion else { return }
        self.pendingDeletion = nil
        switch pendingDeletion {
        case .all: clear()
        case .current(let record): remove(record, clearingClipboard: true)
        }
    }

    private func clearClipboard() {
        pasteboard.clearContents()
        lastChange = pasteboard.changeCount
        if currentRecordID != nil { currentRecordID = nil }
        if notice != nil { notice = nil }
    }

    func clear() {
        guard !isLoading, !isTerminating, !isChangingStorage else { return }
        history.clear()
        clearClipboard()
        thumbnails.removeAll()
        if notice != nil { notice = nil }
        scheduleSave()
    }

    func remove(_ record: ClipRecord) {
        remove(record, clearingClipboard: currentRecordID == record.id)
    }

    private func remove(_ record: ClipRecord, clearingClipboard: Bool) {
        guard !isLoading, !isTerminating, !isChangingStorage else { return }
        history.remove(id: record.id)
        if clearingClipboard { clearClipboard() }
        thumbnails.removeValue(forKey: record.id)
        scheduleSave()
    }

    func setSavesToDisk(_ enabled: Bool) async {
        guard !isChangingStorage, !isLoading, !isTerminating, enabled != savesToDisk else { return }
        isChangingStorage = true
        defer { isChangingStorage = false }
        await persistenceTask?.value
        do {
            if enabled { try await archive.save(history) }
            else { try await archive.remove() }
            savesToDisk = enabled
            preferences.set(enabled, forKey: "saveHistoryToDisk")
            diskError = nil
        } catch {
            diskError = "更改保存设置失败：\(error.localizedDescription)"
        }
    }

    private func scheduleSave() {
        guard savesToDisk, !isChangingStorage, !isTerminating else { return }
        persistenceRevision += 1
        let revision = persistenceRevision
        let previous = persistenceTask
        persistenceTask = Task { [weak self] in
            await previous?.value
            guard let self, self.savesToDisk, revision == self.persistenceRevision else { return }
            do {
                try await self.archive.save(self.history)
                if revision == self.persistenceRevision { self.diskError = nil }
            } catch {
                self.diskError = "保存本地历史失败：\(error.localizedDescription)"
            }
        }
    }

    func flush() async -> Bool {
        await startupTask?.value
        await persistenceTask?.value
        guard savesToDisk else { return true }
        do {
            try await archive.save(history)
            diskError = nil
            return true
        } catch {
            diskError = "保存本地历史失败：\(error.localizedDescription)"
            return false
        }
    }

    func prepareToQuit() async -> Bool {
        guard !isChangingStorage else { return false }
        isTerminating = true
        let success = await flush()
        if !success { isTerminating = false }
        return success
    }

    func thumbnail(for record: ClipRecord) -> NSImage? {
        if let cached = thumbnails[record.id] { return cached }
        guard case .image(let data, _) = record.content,
              let image = Self.makeThumbnail(data) else { return nil }
        thumbnails[record.id] = image
        return image
    }

    private static func makeThumbnail(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 240,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
