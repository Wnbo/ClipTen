import AppKit
import Combine
import Testing
@testable import ClipTen

@MainActor
struct PollingTests {
    @Test func idlePollingCachesPermissionAndDoesNotPublishRepeatedState() {
        var now: TimeInterval = 100
        var reads = 0
        let store = ClipboardStore(
            pasteboard: NSPasteboard(name: .init("ClipTen.PollingTests.\(UUID())")),
            preferences: UserDefaults(suiteName: "ClipTen.PollingTests.\(UUID())")!,
            uptime: { now }, readAccess: { reads += 1; return .denied })
        store.poll()
        #expect(reads == 1)
        #expect(store.permissionNotice != nil)
        var updates = 0
        let observation = store.objectWillChange.sink { updates += 1 }
        for tick in 1...9 {
            now = 100 + Double(tick) * 0.5
            store.poll()
        }
        #expect(reads == 1)
        #expect(updates == 0)
        now = 105
        store.poll()
        #expect(reads == 2)
        #expect(updates == 0)
        withExtendedLifetime(observation) {}
    }

    @Test func explicitRefreshBypassesCacheAndUnchangedMessageStaysSilent() {
        var access = ClipboardStore.ClipboardAccess.denied
        var reads = 0
        let store = ClipboardStore(
            pasteboard: NSPasteboard(name: .init("ClipTen.PollingTests.\(UUID())")),
            preferences: UserDefaults(suiteName: "ClipTen.PollingTests.\(UUID())")!,
            uptime: { 100 }, readAccess: { reads += 1; return access })
        store.poll()
        var updates = 0
        let observation = store.objectWillChange.sink { updates += 1 }
        store.poll(refreshPermissions: true)
        #expect(reads == 2)
        #expect(updates == 0)
        access = .allowed
        store.poll(refreshPermissions: true)
        #expect(reads == 3)
        #expect(store.permissionNotice == nil)
        #expect(updates == 1)
        store.poll()
        #expect(reads == 3)
        #expect(updates == 1)
        withExtendedLifetime(observation) {}
    }
}
