import Foundation
import XCTest
@testable import ClipTenCore

final class HistoryTests: XCTestCase {
    func testCurrentMatchCanSelectAnOlderRecordAndRequiresExactContent() {
        var history = ClipHistory()
        history.insert(.text("old\ntext"))
        let oldID = history.records[0].id
        history.insert(.text("new"))
        XCTAssertEqual(history.matchingRecordID(for: .text("old\ntext")), oldID)
        XCTAssertNil(history.matchingRecordID(for: .text("old text")))
        XCTAssertNil(history.matchingRecordID(for: nil))
        history.remove(id: oldID)
        XCTAssertNil(history.matchingRecordID(for: .text("old\ntext")))
    }

    func testCurrentImageMatchUsesBytesAndRepresentation() {
        var history = ClipHistory()
        history.insert(.image(Data([1, 2, 3]), type: "public.png"))
        let imageID = history.records[0].id
        XCTAssertEqual(history.matchingRecordID(for: .image(Data([1, 2, 3]), type: "public.png")), imageID)
        XCTAssertNil(history.matchingRecordID(for: .image(Data([1, 2, 4]), type: "public.png")))
        XCTAssertNil(history.matchingRecordID(for: .image(Data([1, 2, 3]), type: "public.tiff")))
    }

    func testRemovingOneEntryPreservesRemainingOrderAndIdentity() {
        var history = ClipHistory()
        history.insert(.text("one"))
        history.insert(.text("two"))
        history.insert(.text("three"))
        let original = history.records
        history.remove(id: original[1].id)
        XCTAssertEqual(history.records.map(\.id), [original[0].id, original[2].id])
        history.remove(id: original[1].id)
        XCTAssertEqual(history.records.count, 2)
    }

    func testHistoryEvictsOldestAndKeepsLatestFirst() {
        var history = ClipHistory()
        for number in 0..<12 { history.insert(.text("\(number)")) }
        XCTAssertEqual(history.records.count, 10)
        XCTAssertEqual(history.records.first?.content, .text("11"))
        XCTAssertEqual(history.records.last?.content, .text("2"))
    }

    func testDuplicateMovesToTopWithoutConsumingSlot() {
        var history = ClipHistory()
        history.insert(.text("first"))
        history.insert(.text("second"))
        history.insert(.text("first"))
        XCTAssertEqual(history.records.count, 2)
        XCTAssertEqual(history.records.first?.content, .text("first"))
    }

    func testImageDataRemainsExactAndClearReleasesHistory() {
        var history = ClipHistory()
        let image = ClipContent.image(Data([0, 255, 1, 2]), type: "public.png")
        history.insert(image)
        XCTAssertEqual(history.records.first?.content, image)
        history.clear()
        XCTAssertTrue(history.records.isEmpty)
    }

    func testFilesTakePrecedenceOverImageOrTextRepresentations() {
        XCTAssertTrue(CapturePolicy.containsFile(["public.png", "public.file-url", "public.utf8-plain-text"]))
        XCTAssertTrue(CapturePolicy.containsFile(["NSFilenamesPboardType"]))
        XCTAssertTrue(CapturePolicy.containsFile(["com.apple.pasteboard.promised-file-url"]))
        XCTAssertTrue(CapturePolicy.containsFile(["com.apple.pasteboard.promised-file-content-type"]))
        XCTAssertFalse(CapturePolicy.containsFile(["public.png", "public.url"]))
        XCTAssertFalse(CapturePolicy.containsFile(["public.utf8-plain-text"]))
    }

    func testSensitiveClipboardMarkersAreSkipped() {
        XCTAssertTrue(CapturePolicy.isSensitive(["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertTrue(CapturePolicy.isSensitive(["org.nspasteboard.TransientType"]))
        XCTAssertFalse(CapturePolicy.isSensitive(["public.utf8-plain-text"]))
    }
}
