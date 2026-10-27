import Foundation
import Testing
@testable import ClipTenCore

struct LockedHistoryTests {
    @Test func sevenLocksSurviveNewCopiesAndEighthLockIsRejected() {
        var history = ClipHistory()
        for number in 0..<7 {
            history.insert(.text("locked \(number)"))
            let toggled1 = history.toggleLock(id: history.records[0].id)
            #expect(toggled1)
        }
        let lockedIDs = history.records.map(\.id)
        for number in 0..<20 { history.insert(.text("new \(number)")) }
        #expect(history.records.count == 10)
        #expect(history.lockedCount == 7)
        #expect(history.records.filter(\.isLocked).map(\.id) == lockedIDs)
        #expect(history.records.filter { !$0.isLocked }.map(\.content) == [.text("new 19"), .text("new 18"), .text("new 17")])
        let toggled2 = history.toggleLock(id: history.records[0].id)
        #expect(!toggled2)
        let toggled3 = history.toggleLock(id: lockedIDs[0])
        #expect(toggled3)
        let toggled4 = history.toggleLock(id: history.records[0].id)
        #expect(toggled4)
        #expect(history.lockedCount == 7)
    }

    @Test func lockAndUnlockPreserveOrderAndRecopyPreservesIdentity() {
        var history = ClipHistory()
        history.insert(.text("first"))
        let id = history.records[0].id
        history.insert(.text("second"))
        let order = history.records.map(\.id)
        let toggled5 = history.toggleLock(id: id)
        #expect(toggled5)
        #expect(history.records.map(\.id) == order)
        let copiedAt = Date(timeIntervalSince1970: 1234)
        history.insert(.text("first"), at: copiedAt)
        #expect(history.records.count == 2)
        #expect(history.records[0].id == id)
        #expect(history.records[0].isLocked)
        #expect(history.records[0].copiedAt == copiedAt)
        let toggled6 = history.toggleLock(id: id)
        #expect(toggled6)
        #expect(history.records[0].id == id)
        #expect(!history.records[0].isLocked)
    }

    @Test func clearAndDeleteProtectLockedImagesUntilUnlocked() {
        var history = ClipHistory()
        history.insert(.image(Data([1, 2, 3]), type: "public.png"))
        let id = history.records[0].id
        history.toggleLock(id: id)
        history.insert(.text("other"))
        history.remove(id: id)
        #expect(history.records.count == 2)
        history.clear()
        #expect(history.records.map(\.id) == [id])
        history.toggleLock(id: id)
        #expect(history.records.count == 1)
        history.remove(id: id)
        #expect(history.records.isEmpty)
    }

    @Test func lockStateRoundTripsAndLegacyArchiveDefaultsToUnlocked() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipTenLocks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.plist")
        let archive = HistoryArchive(fileURL: url)
        var history = ClipHistory()
        history.insert(.text("saved"))
        let id = history.records[0].id
        history.toggleLock(id: id)
        try await archive.save(history)
        let loaded = try #require(try await archive.load())
        #expect(loaded.records[0].id == id)
        #expect(loaded.records[0].isLocked)
        // Simulate the existing version-1 archive, which has no lock field.
        var plist = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        var records = try #require(plist["records"] as? [[String: Any]])
        records[0].removeValue(forKey: "isLocked")
        plist["records"] = records
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: url)
        let legacy = try #require(try await archive.load())
        #expect(legacy.records[0].id == id)
        #expect(!legacy.records[0].isLocked)
    }
}
