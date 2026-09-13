import Foundation

enum PopoverGeometry {
    static func contentSize(recordCount: Int, noticeHeight: CGFloat, availableHeight: CGFloat) -> NSSize {
        let rows: CGFloat = recordCount == 0 ? 80 : min(CGFloat(recordCount) * 76 + 16, 460)
        let chrome: CGFloat = recordCount == 0 ? 110 : 130
        return NSSize(width: 360, height: min(rows + chrome + noticeHeight, availableHeight))
    }
}
