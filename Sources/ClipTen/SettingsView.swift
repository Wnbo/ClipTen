import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var loginItems: LoginItemManager

    private var versionLabel: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return "开发版"
        }
        return "v\(version)"
    }

    var body: some View {
      VStack(spacing: 0) {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    settingRow(symbol: "power", tint: .blue, title: "登录时启动",
                               isOn: Binding(get: { loginItems.isRegistered }, set: { value in
                                   Task { await loginItems.setEnabled(value) }
                               }), disabled: loginItems.isChanging) {
                        Text("登录这台 Mac 后自动运行拾贴。")
                        Button { loginItems.openSystemSettings() } label: {
                            HStack(spacing: 3) {
                                Text("系统登录项设置")
                                Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .semibold))
                            }.foregroundStyle(Color.accentColor)
                        }.buttonStyle(.plain).interactiveCursor().padding(.top, 2)
                        if loginItems.requiresApproval {
                            Text("等待系统批准").foregroundStyle(.orange)
                        }
                        if let error = loginItems.errorMessage {
                            Text(error).foregroundStyle(.red).textSelection(.enabled)
                        }
                    }

                    Divider().padding(.leading, 56)

                    settingRow(symbol: "internaldrive", tint: .teal, title: "保存历史到硬盘",
                               isOn: Binding(get: { store.savesToDisk }, set: { value in
                                   Task { await store.setSavesToDisk(value) }
                               }), disabled: store.isChangingStorage || store.isLoading) {
                        Text("保留最近 10 条文字和图片，重启后恢复。")
                        Text("关闭后删除磁盘历史，内存记录仍保留。")
                            .foregroundStyle(.tertiary)
                        if store.isChangingStorage {
                            ProgressView().controlSize(.mini).padding(.top, 3)
                        }
                        if let error = store.diskError {
                            Text(error).foregroundStyle(.red).textSelection(.enabled)
                            Button("重试保存") { Task { _ = await store.flush() } }
                                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                                .disabled(!store.savesToDisk || store.isChangingStorage)
                                .interactiveCursor(enabled: store.savesToDisk && !store.isChangingStorage)
                        }
                    }

                    Divider().padding(.leading, 56)

                    settingRow(symbol: "trash", tint: .orange, title: "清空系统剪贴板前确认",
                               isOn: Binding(get: { store.confirmsClipboardClear },
                                             set: { store.setConfirmsClipboardClear($0) }),
                               disabled: false) {
                        Text("清空全部历史或删除带“当前”标记的记录时，也会清空系统剪贴板。")
                        Text("删除其他记录仅移除历史。")
                            .foregroundStyle(.tertiary)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
                }

                Label("仅保存在本机，不上传或同步", systemImage: "lock")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        Text("\(versionLabel) · Wnbo & Codex")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
      }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 420, height: 370)
        .onAppear { loginItems.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItems.refresh()
        }
    }

    private func settingRow<Description: View>(symbol: String, tint: Color, title: String,
                                              isOn: Binding<Bool>, disabled: Bool,
                                              @ViewBuilder description: () -> Description) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 4, content: description)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)

            Toggle(title, isOn: isOn)
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                .disabled(disabled)
                .interactiveCursor(enabled: !disabled)
                .frame(width: 32, alignment: .trailing)
                .padding(.top, 1)
        }.padding(14)
    }
}
