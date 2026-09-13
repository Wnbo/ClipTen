import AppKit
import ClipTenCore
import Testing
@testable import ClipTen

/// Preference writes stay in this test object, never in the user's defaults.
private final class MemoryPreferences: UserDefaults, @unchecked Sendable {
    private let mutex = NSLock()
    private var values: [String: Bool] = [:]

    override func object(forKey defaultName: String) -> Any? {
        mutex.withLock { values[defaultName] }
    }

    override func bool(forKey defaultName: String) -> Bool {
        mutex.withLock { values[defaultName] ?? false }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        mutex.withLock { values[defaultName] = value as? Bool }
    }
}

@MainActor
struct PersistenceSettingsTests {
    private func fixture(_ body: @MainActor (ClipboardStore, HistoryArchive, MemoryPreferences, URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipTenSettingsTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferences = MemoryPreferences(suiteName: "ClipTen.TestOnly.\(UUID())")!
        let archive = HistoryArchive(fileURL: directory.appendingPathComponent("history.plist"))
        // No operations are performed on the system general clipboard. These
        // tests exercise storage/settings; real pasteboard tests remain opt-in.
        let store = ClipboardStore(pasteboard: NSPasteboard(name: .init("ClipTen.TestOnly.\(UUID())")),
                                   preferences: preferences, archive: archive)
        try await body(store, archive, preferences, directory)
    }

    @Test func clipboardConfirmationDefaultsOnAndPersistsOff() async throws {
        try await fixture { store, archive, preferences, _ in
            #expect(store.confirmsClipboardClear)
            store.requestClear()
            #expect(store.pendingDeletion != nil)
            store.cancelDeletion()
            #expect(store.pendingDeletion == nil)
            store.setConfirmsClipboardClear(false)
            let reloaded = ClipboardStore(pasteboard: NSPasteboard(name: .init("ClipTen.TestOnly.\(UUID())")),
                                          preferences: preferences, archive: archive)
            #expect(!reloaded.confirmsClipboardClear)
            reloaded.setConfirmsClipboardClear(true)
            #expect(preferences.bool(forKey: "confirmClipboardClear"))
        }
    }

    @Test func enablingWritesImmediatelyAndDisablingRemovesFile() async throws {
        try await fixture { store, archive, preferences, _ async throws in
            #expect(!store.savesToDisk)
            await store.setSavesToDisk(true)
            #expect(store.savesToDisk)
            #expect(preferences.bool(forKey: "saveHistoryToDisk"))
            #expect(try await archive.load() != nil)
            await store.setSavesToDisk(false)
            #expect(!store.savesToDisk)
            #expect(!preferences.bool(forKey: "saveHistoryToDisk"))
            #expect(try await archive.load() == nil)
            #expect(await store.flush())
            #expect(try await archive.load() == nil)
        }
    }

    @Test func loadedRecordsDeletePersistAndSurviveTurningPersistenceOffInMemory() async throws {
        try await fixture { _, archive, preferences, _ in
            var history = ClipHistory()
            history.insert(.text("keep"))
            history.insert(.text("delete"))
            try await archive.save(history)
            preferences.set(true, forKey: "saveHistoryToDisk")
            let store = ClipboardStore(pasteboard: NSPasteboard(name: .init("ClipTen.TestOnly.\(UUID())")),
                                       preferences: preferences, archive: archive)
            await store.loadSavedHistory()
            store.remove(try #require(store.history.records.first))
            #expect(await store.flush())
            #expect(try await archive.load()?.records.map(\.content) == [.text("keep")])
            await store.setSavesToDisk(false)
            #expect(store.history.records.map(\.content) == [.text("keep")])
            #expect(try await archive.load() == nil)
            await store.setSavesToDisk(true)
            #expect(try await archive.load()?.records.map(\.content) == [.text("keep")])
        }
    }

    @Test func queuedSaveCannotRecreateArchiveAfterDisable() async throws {
        try await fixture { store, archive, _, _ async throws in
            await store.setSavesToDisk(true)
            store.clear()
            store.clear()
            await store.setSavesToDisk(false)
            #expect(await store.flush())
            #expect(try await archive.load() == nil)
        }
    }

    @Test func writeFailureDoesNotClaimSettingWasEnabled() async throws {
        try await fixture { store, _, preferences, directory in
            // A regular file where the archive directory should be is a reliable
            // failure even when tests run as an administrator.
            try Data("block directory creation".utf8).write(to: directory)
            await store.setSavesToDisk(true)
            #expect(!store.savesToDisk)
            #expect(!preferences.bool(forKey: "saveHistoryToDisk"))
            #expect(store.diskError != nil)
            #expect(!store.isChangingStorage)
        }
    }
}
