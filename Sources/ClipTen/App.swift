import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private let store = ClipboardStore()
    private var previousApplication: NSRunningApplication?
    private let loginItems = LoginItemManager()
    private var settingsWindow: NSWindow?
    private var waitingForTermination = false
    private var layoutUpdateScheduled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "拾贴")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "拾贴 · ClipTen"
            button.target = self
            button.action = #selector(togglePopover)
        }
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = false
        store.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        store.poll(refreshPermissions: true)
    }

    private func popoverSize(for button: NSStatusBarButton) -> NSSize {
        let noticesHeight: CGFloat = (store.notice == nil ? 0 : 60) + (store.permissionNotice == nil ? 0 : 80)
            + (store.diskError == nil ? 0 : 40)
        let availableHeight = max(180, (button.window?.screen?.visibleFrame.height ?? 800) - 32)
        return PopoverGeometry.contentSize(recordCount: store.history.records.count,
                                           noticeHeight: noticesHeight, availableHeight: availableHeight)
    }

    private func historyView() -> HistoryView {
        HistoryView(store: store,
            openSettings: { [weak self] in self?.showSettings() },
            layoutDidChange: { [weak self] in self?.schedulePopoverResize() }) { [weak self] record in
            guard let self else { return }
            if self.store.restore(record) {
                self.popover.performClose(nil)
                self.previousApplication?.activate(options: [])
            }
        }
    }

    private func preparePopover(for button: NSStatusBarButton) {
        let size = popoverSize(for: button)
        let controller = NSHostingController(rootView: historyView())
        // The native popover is the sole owner of height. SwiftUI fills its
        // container instead of retaining a second, fixed height after deletion.
        controller.sizingOptions = []
        controller.view.autoresizingMask = [.width, .height]
        controller.view.setFrameSize(size)
        controller.view.layoutSubtreeIfNeeded()
        popover.contentViewController = controller
        popover.contentSize = size
    }

    private func schedulePopoverResize() {
        guard popover.isShown, !layoutUpdateScheduled else { return }
        layoutUpdateScheduled = true
        // Wait until the current SwiftUI update completes, and coalesce changes.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutUpdateScheduled = false
            self.resizePopover()
        }
    }

    private func resizePopover() {
        guard popover.isShown, let button = statusItem.button, button.window != nil else { return }
        let size = popoverSize(for: button)
        guard size != popover.contentSize else { return }
        // Resize the existing window in place. AppKit animates contentSize and
        // keeps its positioning view attached. No close/re-show or frame edits.
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentSize = size
    }

    private func showSettings() {
        popover.performClose(nil)
        loginItems.refresh()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 370),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "拾贴设置"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(store: store, loginItems: loginItems))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !store.isChangingStorage else { return .terminateCancel }
        guard !waitingForTermination else { return .terminateLater }
        waitingForTermination = true
        Task {
            var canQuit = await store.prepareToQuit()
            if !canQuit {
                let alert = NSAlert()
                alert.messageText = "最新历史尚未保存"
                alert.informativeText = store.diskError ?? "请等待设置保存完成后重试。"
                alert.addButton(withTitle: "取消退出")
                alert.addButton(withTitle: "仍然退出")
                canQuit = alert.runModal() == .alertSecondButtonReturn
            }
            waitingForTermination = false
            sender.reply(toApplicationShouldTerminate: canQuit)
        }
        return .terminateLater
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button, button.window != nil else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            previousApplication = NSWorkspace.shared.frontmostApplication
            store.poll(refreshPermissions: true)
            preparePopover(for: button)
            NSApp.activate(ignoringOtherApps: true)
            let bottomEdge: NSRectEdge = button.isFlipped ? .maxY : .minY
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: bottomEdge)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

@main
struct ClipTenApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
