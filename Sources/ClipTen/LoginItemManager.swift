import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorMessage: String?
    @Published private(set) var isChanging = false

    var isRegistered: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }

    func setEnabled(_ enabled: Bool) async {
        guard !isChanging else { return }
        isChanging = true
        defer { isChanging = false; refresh() }
        refresh()
        do {
            if enabled && !isRegistered { try SMAppService.mainApp.register() }
            else if !enabled && isRegistered { try await SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch {
            errorMessage = "登录项设置失败：\(error.localizedDescription)"
        }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
