import AppKit
import ClipTenCore
import SwiftUI

struct PreviewGeometry {
    static func fitScale(image: CGSize, viewport: CGSize) -> CGFloat {
        guard image.width > 0, image.height > 0 else { return 1 }
        return max(0.001, min(1, min(max(1, viewport.width - 32) / image.width,
                                    max(1, viewport.height - 32) / image.height)))
    }

    static func initialSize(image: CGSize, screen: CGSize) -> CGSize {
        let limit = CGSize(width: min(1000, screen.width * 0.85), height: min(800, screen.height * 0.85))
        let scale = fitScale(image: image, viewport: CGSize(width: limit.width, height: limit.height - 100))
        return CGSize(width: min(limit.width, max(480, image.width * scale + 32)),
                      height: min(limit.height, max(360, image.height * scale + 132)))
    }
}

@MainActor
final class ImagePreviewController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init?(record: ClipRecord, copy: @escaping () -> Bool) {
        guard case .image(let data, _) = record.content,
              let image = NSImage(data: data),
              let representation = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide }),
              representation.pixelsWide > 0, representation.pixelsHigh > 0 else { return nil }
        let pixels = CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        let size = PreviewGeometry.initialSize(image: pixels, screen: screen)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "图片预览 · 拾贴"
        window.isReleasedWhenClosed = false
        window.contentMinSize = CGSize(width: min(480, size.width), height: min(300, size.height))
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ImagePreviewView(image: image, pixels: pixels,
            copy: copy, close: { [weak self] in self?.close() }))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        onClose?()
    }
}

private struct ImagePreviewView: View {
    let image: NSImage
    let pixels: CGSize
    let copy: () -> Bool
    let close: () -> Void
    @State private var customScale: CGFloat?
    @State private var copyMessage: String?

    var body: some View {
        GeometryReader { geometry in
            let viewport = CGSize(width: geometry.size.width, height: max(1, geometry.size.height - 94))
            let scale = customScale ?? PreviewGeometry.fitScale(image: pixels, viewport: viewport)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button("适合窗口") { customScale = nil }
                    Button("100%") { customScale = 1 }
                        .help("按图片像素尺寸显示（一个像素对应一个界面点）")
                    Spacer()
                    Button { customScale = max(0.001, scale / 1.25) } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }.accessibilityLabel("缩小").disabled(scale <= 0.001)
                    Text(String(format: "%.0f%%", scale * 100))
                        .monospacedDigit().frame(width: 50)
                    Button { customScale = min(8, scale * 1.25) } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }.accessibilityLabel("放大").disabled(scale >= 8)
                }.padding(.horizontal, 14).frame(height: 46)
                Divider()
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable().interpolation(.high)
                        .frame(width: pixels.width * scale, height: pixels.height * scale)
                        .padding(16)
                        .frame(minWidth: viewport.width, minHeight: viewport.height, alignment: .center)
                        .accessibilityLabel("原始图片预览")
                }
                .background(Color(nsColor: .underPageBackgroundColor))
                Divider()
                HStack {
                    Text("\(Int(pixels.width)) × \(Int(pixels.height))")
                        .foregroundStyle(.secondary)
                    if let copyMessage { Text(copyMessage).foregroundStyle(.secondary) }
                    Spacer()
                    Button("关闭", action: close).keyboardShortcut(.cancelAction)
                    Button("复制图片") { copyMessage = copy() ? "已复制" : "复制失败，请重试" }
                        .keyboardShortcut("c", modifiers: .command)
                }.padding(.horizontal, 14).frame(height: 46)
            }.font(.system(size: 12))
        }
    }
}
