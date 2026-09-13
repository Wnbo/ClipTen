import AppKit
import ClipTenCore
import Testing
@testable import ClipTen

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CLIPTEN_INTEGRATION_TESTS"] == "1"))
struct ClipboardTests {
    private func withPasteboard(_ body: (NSPasteboard, ClipboardStore) throws -> Void) rethrows {
        let board = NSPasteboard.withUniqueName()
        let suite = "ClipTenTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer {
            board.releaseGlobally()
            preferences.removePersistentDomain(forName: suite)
        }
        board.clearContents()
        try body(board, ClipboardStore(pasteboard: board, preferences: preferences))
    }

    @Test func permissionRecoveryRecapturesUnchangedClipboardAndChangesBypassCache() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        try #require(board.setString("before denial", forType: .string))
        var now: TimeInterval = 100
        var access = ClipboardStore.ClipboardAccess.allowed
        var reads = 0
        let preferences = UserDefaults(suiteName: "ClipTen.PollingTests.\(UUID())")!
        let store = ClipboardStore(pasteboard: board, preferences: preferences, uptime: { now },
                                   readAccess: { reads += 1; return access })
        store.poll()
        #expect(store.currentRecordID != nil)
        access = .denied
        store.poll(refreshPermissions: true)
        #expect(store.currentRecordID == nil)
        access = .allowed
        now = 105
        store.poll()
        #expect(store.currentRecordID != nil)
        #expect(store.history.records.count == 1)
        #expect(reads == 3)
        board.clearContents()
        try #require(board.setString("new copy", forType: .string))
        store.poll()
        #expect(reads == 4)
        #expect(store.history.records.first?.content == .text("new copy"))
    }

    @Test func textRoundTripAndSelfWriteDoesNotDuplicate() throws {
        try withPasteboard { board, store in
            let text = "拾贴测试 👋\n第二行\t完整保留"
            try #require(board.setString(text, forType: .string))
            store.poll()
            #expect(store.history.records.count == 1)
            let record = try #require(store.history.records.first)
            #expect(store.currentRecordID == record.id)
            board.clearContents()
            board.setString("another", forType: .string)
            store.poll()
            #expect(store.restore(record))
            #expect(store.currentRecordID == record.id)
            #expect(board.string(forType: .string) == text)
            store.poll()
            #expect(store.history.records.count == 2)
            #expect(store.history.records.first?.content == .text("another"))
        }
    }

    @Test func imageRoundTripUsesFullDataAndThumbnail() throws {
        try withPasteboard { board, store in
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32,
                pixelsHigh: 24, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let item = NSPasteboardItem()
            item.setData(data, forType: .png)
            item.setString("image alt text", forType: .string)
            try #require(board.writeObjects([item]))
            store.poll()
            let record = try #require(store.history.records.first)
            #expect(record.content == .image(data, type: NSPasteboard.PasteboardType.png.rawValue))
            #expect(store.thumbnail(for: record) != nil)
            #expect(store.currentRecordID == record.id)
            #expect(store.restore(record))
            #expect(board.data(forType: .png) == data)
        }
    }

    @Test func copiedFilesAndConcealedTextNeverEnterHistory() throws {
        try withPasteboard { board, store in
            let file = NSPasteboardItem()
            file.setString("file:///tmp/example.png", forType: .fileURL)
            file.setString("example.png", forType: .string)
            try #require(board.writeObjects([file]))
            store.poll()
            #expect(store.history.records.isEmpty)
            board.clearContents()
            let concealed = NSPasteboardItem()
            concealed.setString("secret", forType: .string)
            concealed.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
            try #require(board.writeObjects([concealed]))
            store.poll()
            #expect(store.history.records.isEmpty)
        }
    }

    @Test func clearErasesSystemClipboardWithoutRecapture() throws {
        try withPasteboard { board, store in
            try #require(board.setString("keep", forType: .string))
            store.poll()
            store.clear()
            store.poll()
            #expect(store.history.records.isEmpty)
            #expect(board.string(forType: .string) == nil)
            #expect(store.currentRecordID == nil)
        }
    }

    @Test func deletingOtherRecordPreservesClipboardAndCurrentNeedsConfirmation() throws {
        try withPasteboard { board, store in
            try #require(board.setString("older", forType: .string))
            store.poll()
            let older = try #require(store.history.records.first)
            board.clearContents()
            try #require(board.setString("current", forType: .string))
            store.poll()
            let current = try #require(store.history.records.first)
            store.requestRemove(older)
            #expect(store.pendingDeletion == nil)
            #expect(board.string(forType: .string) == "current")
            store.requestRemove(current)
            #expect(store.pendingDeletion != nil)
            #expect(store.history.records.count == 1)
            store.cancelDeletion()
            #expect(board.string(forType: .string) == "current")
            store.requestRemove(current)
            // Confirmation intentionally clears whatever is present at execution.
            board.clearContents()
            try #require(board.setString("changed while confirming", forType: .string))
            store.poll()
            store.confirmDeletion()
            #expect(board.string(forType: .string) == nil)
            #expect(store.currentRecordID == nil)
            #expect(!store.history.records.contains { $0.id == current.id })
        }
    }

    @Test func confirmationDisabledDeletesImmediatelyAndClearCanBeCancelled() throws {
        try withPasteboard { board, store in
            try #require(board.setString("current", forType: .string))
            store.poll()
            store.requestClear()
            #expect(board.string(forType: .string) == "current")
            store.cancelDeletion()
            #expect(store.history.records.count == 1)
            store.setConfirmsClipboardClear(false)
            store.requestRemove(try #require(store.history.records.first))
            #expect(store.pendingDeletion == nil)
            #expect(board.string(forType: .string) == nil)
            try #require(board.setString("next", forType: .string))
            store.poll()
            store.requestClear()
            #expect(store.history.records.isEmpty)
            #expect(board.string(forType: .string) == nil)
        }
    }

    @Test func currentMarkerClearsWhenClipboardBecomesAFileOrEmpty() throws {
        try withPasteboard { board, store in
            try #require(board.setString("text", forType: .string))
            store.poll()
            #expect(store.currentRecordID != nil)
            board.clearContents()
            try #require(board.setString("file:///tmp/example.png", forType: .fileURL))
            store.poll()
            #expect(store.currentRecordID == nil)
            #expect(store.history.records.count == 1)
            board.clearContents()
            store.poll()
            #expect(store.currentRecordID == nil)
        }
    }

    @Test func readingCurrentWithoutRecordingDoesNotResurrectDeletedHistory() throws {
        try withPasteboard { board, store in
            try #require(board.setString("deleted earlier", forType: .string))
            store.poll(recordChanges: false)
            #expect(store.currentRecordID == nil)
            #expect(store.history.records.isEmpty)
        }
    }
}
