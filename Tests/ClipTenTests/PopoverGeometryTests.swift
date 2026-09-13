import Foundation
import ClipTenCore
import Testing
@testable import ClipTen

struct PopoverGeometryTests {
    @Test func removingRowsShrinksThroughTheLastRecord() throws {
        var history = ClipHistory()
        for index in 0..<5 { history.insert(.text("\(index)")) }
        var previous = size(history).height
        while let record = history.records.first {
            history.remove(id: record.id)
            let next = size(history).height
            #expect(next < previous)
            previous = next
        }
        #expect(previous == 190)
    }

    @Test func clearingAllUsesTheSameCompactEmptySize() {
        var history = ClipHistory()
        for index in 0..<10 { history.insert(.text("\(index)")) }
        let fullHeight = size(history).height
        history.clear()
        #expect(size(history).height < fullHeight)
        #expect(size(history) == size(ClipHistory()))
    }

    @Test func contentFitsShortScreensAndLargeHistoriesStayScrollable() {
        #expect(PopoverGeometry.contentSize(recordCount: 10, noticeHeight: 180, availableHeight: 400).height == 400)
        #expect(PopoverGeometry.contentSize(recordCount: 10, noticeHeight: 0, availableHeight: 800).height ==
                PopoverGeometry.contentSize(recordCount: 6, noticeHeight: 0, availableHeight: 800).height)
    }

    private func size(_ history: ClipHistory) -> NSSize {
        PopoverGeometry.contentSize(recordCount: history.records.count, noticeHeight: 0, availableHeight: 800)
    }
}
