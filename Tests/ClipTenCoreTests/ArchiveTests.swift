import Foundation
import Testing
@testable import ClipTenCore

struct ArchiveTests {
    private func withArchive(_ body: (HistoryArchive, URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipTenArchiveTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(HistoryArchive(fileURL: directory.appendingPathComponent("history.plist")), directory)
    }

    @Test func textAndImageSurviveReloadWithIdentityOrderAndDates() async throws {
        try await withArchive { archive, _ in
            var history = ClipHistory()
            history.insert(.text("第一行\nSecond line 👋"), at: Date(timeIntervalSince1970: 100))
            history.insert(.image(Data([1, 0, 255, 8]), type: "public.png"), at: Date(timeIntervalSince1970: 200))
            try await archive.save(history)
            let reloaded = try #require(try await archive.load())
            #expect(reloaded.records.map(\.id) == history.records.map(\.id))
            #expect(reloaded.records.map(\.content) == history.records.map(\.content))
            #expect(reloaded.records.map(\.copiedAt) == history.records.map(\.copiedAt))
        }
    }

    @Test func deletionAndEmptyHistoryPersistAcrossReload() async throws {
        try await withArchive { archive, _ in
            var history = ClipHistory()
            history.insert(.text("delete"))
            let deletedID = try #require(history.records.first?.id)
            history.insert(.text("keep"))
            history.remove(id: deletedID)
            try await archive.save(history)
            let reloaded = try #require(try await archive.load())
            #expect(reloaded.records.count == 1)
            #expect(reloaded.records.first?.content == .text("keep"))
            history.clear()
            try await archive.save(history)
            let empty = try #require(try await archive.load())
            #expect(empty.records.isEmpty)
        }
    }

    @Test func capacityIsStillTenAfterRestart() async throws {
        try await withArchive { archive, _ in
            var history = ClipHistory()
            for index in 0..<15 { history.insert(.text("\(index)")) }
            try await archive.save(history)
            let loaded = try #require(try await archive.load())
            #expect(loaded.records.count == 10)
            #expect(loaded.records.first?.content == .text("14"))
            #expect(loaded.records.last?.content == .text("5"))
        }
    }

    @Test func disablingRemovesOnlyArchiveAndIsIdempotent() async throws {
        try await withArchive { archive, directory in
            try await archive.save(ClipHistory())
            let unrelated = directory.appendingPathComponent("keep.txt")
            try Data("untouched".utf8).write(to: unrelated)
            try await archive.remove()
            try await archive.remove()
            #expect(try await archive.load() == nil)
            #expect(try String(contentsOf: unrelated, encoding: .utf8) == "untouched")
        }
    }

    @Test func corruptArchiveReportsFailureWithoutSilentlyClearingFile() async throws {
        try await withArchive { archive, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = await archive.fileURL
            let invalid = Data("not a plist".utf8)
            try invalid.write(to: file)
            await #expect(throws: (any Error).self) { try await archive.load() }
            #expect(try Data(contentsOf: file) == invalid)
        }
    }

    @Test func rejectedWritePreservesPreviousArchiveAndFilesArePrivate() async throws {
        try await withArchive { archive, directory in
            var valid = ClipHistory()
            valid.insert(.text("keep"))
            try await archive.save(valid)
            var invalid = ClipHistory()
            invalid.insert(.image(Data([1]), type: "public.file-url"))
            await #expect(throws: HistoryArchive.ArchiveError.self) { try await archive.save(invalid) }
            #expect(try await archive.load()?.records.first?.content == .text("keep"))
            let file = await archive.fileURL
            let fileMode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
            let directoryMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
            #expect(fileMode?.intValue == 0o600)
            #expect(directoryMode?.intValue == 0o700)
        }
    }
}
