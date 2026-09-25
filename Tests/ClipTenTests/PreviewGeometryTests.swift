import Foundation
import Testing
@testable import ClipTen

struct PreviewGeometryTests {
    @Test func longScreenshotFitsBothDimensions() {
        let image = CGSize(width: 1200, height: 18000)
        let viewport = CGSize(width: 800, height: 600)
        let scale = PreviewGeometry.fitScale(image: image, viewport: viewport)
        // Scaling can exceed the exact boundary by a floating-point rounding error.
        #expect(image.width * scale <= viewport.width - 32 + 0.000001)
        #expect(image.height * scale <= viewport.height - 32 + 0.000001)
        #expect(scale > 0)
    }

    @Test func smallImagesAreNotUpscaledAndWindowStaysOnScreen() {
        #expect(PreviewGeometry.fitScale(image: CGSize(width: 100, height: 80),
                                        viewport: CGSize(width: 800, height: 600)) == 1)
        for image in [CGSize(width: 18000, height: 500), CGSize(width: 500, height: 18000)] {
            let size = PreviewGeometry.initialSize(image: image, screen: CGSize(width: 1024, height: 700))
            #expect(size.width <= 1024 * 0.85)
            #expect(size.height <= 700 * 0.85)
            #expect(size.width >= 480)
            #expect(size.height >= 360)
        }
    }
}
