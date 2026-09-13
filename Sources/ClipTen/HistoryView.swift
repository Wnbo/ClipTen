import AppKit
import ClipTenCore
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: ClipboardStore
    let openSettings: () -> Void
    let layoutDidChange: () -> Void
    let select: (ClipRecord) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("拾贴").font(.headline)
                    Text(store.history.records.isEmpty ? "剪贴板历史" : "ClipTen · 最近 \(store.history.records.count)/10 条")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "gearshape").font(.system(size: 16))
                }.buttonStyle(HoverButtonStyle()).help("设置").accessibilityLabel("设置")
            }.padding(16)
            Divider()

            if let permissionNotice = store.permissionNotice {
                Text(permissionNotice).font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            if let notice = store.notice {
                Text(notice).font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            if let error = store.diskError {
                Button("本地历史异常，点击查看设置") { openSettings() }
                    .font(.caption).foregroundStyle(.red).buttonStyle(.plain).padding(8)
                    .help(error)
                    .interactiveCursor()
            }
            if store.history.records.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(Color.secondary.opacity(0.65))
                        .frame(width: 42, height: 42)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.isLoading ? "正在读取历史…" : "暂无复制记录")
                            .font(.system(size: 13, weight: .medium))
                        Text(store.isLoading ? "已保存的记录即将显示" : "复制文字或图片，即可在这里找回。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.history.records) { record in
                            ClipRow(record: record, thumbnail: store.thumbnail(for: record),
                                    isCurrent: store.currentRecordID == record.id,
                                    action: { select(record) }, remove: { store.requestRemove(record) })
                        }
                    }.padding(8)
                }.frame(maxHeight: .infinity)
            }

            Divider()
            HStack {
                if store.history.records.isEmpty {
                    Text(store.savesToDisk ? "已开启本地保存" : "仅保存在内存中")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                } else {
                    Text("点击恢复，再按 ⌘V 粘贴").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !store.history.records.isEmpty {
                    Button("清空") { store.requestClear() }.disabled(store.isLoading)
                        .buttonStyle(HoverButtonStyle(tint: .red))
                }
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(HoverButtonStyle())
            }.font(.caption).padding(12)
            if !store.history.records.isEmpty {
                Text(store.savesToDisk ? "已开启本地保存 · 重启后恢复" : "仅保存在内存中 · 退出后清空")
                    .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.bottom, 10)
            }
        }.frame(width: 360)
        .frame(maxHeight: .infinity, alignment: .top)
        .disabled(store.pendingDeletion != nil)
        .overlay {
            if let deletion = store.pendingDeletion {
                ZStack {
                    Color.black.opacity(0.12).contentShape(Rectangle())
                    VStack(alignment: .leading, spacing: 10) {
                        Text(deletionTitle(deletion)).font(.system(size: 13, weight: .semibold))
                        Text("系统剪贴板也会被清空，之后无法直接粘贴当前内容。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Spacer()
                            Button("取消") { store.cancelDeletion() }
                                .keyboardShortcut(.cancelAction)
                                .buttonStyle(HoverButtonStyle())
                            Button("确认清空") { store.confirmDeletion() }
                                .buttonStyle(HoverButtonStyle(tint: .red))
                        }.font(.system(size: 12))
                    }
                    .padding(16).frame(width: 288)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.2)))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                }
            }
        }
        .onDisappear { store.cancelDeletion() }
        .onChange(of: store.history.records.count) { _ in layoutDidChange() }
        .onChange(of: store.notice != nil) { _ in layoutDidChange() }
        .onChange(of: store.permissionNotice != nil) { _ in layoutDidChange() }
        .onChange(of: store.diskError != nil) { _ in layoutDidChange() }
    }
    private func deletionTitle(_ deletion: ClipboardStore.PendingDeletion) -> String {
        switch deletion {
        case .all: return "清空全部历史和系统剪贴板？"
        case .current: return "删除当前记录并清空系统剪贴板？"
        }
    }
}

private struct ClipRow: View {
    let record: ClipRecord
    let thumbnail: NSImage?
    let isCurrent: Bool
    let action: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
          Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08))
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFit().padding(3)
                    } else {
                        Image(systemName: "text.alignleft").font(.title3).foregroundStyle(.secondary)
                    }
                }.frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 5) {
                    switch record.content {
                    case .text(let text):
                        Text(String(text.prefix(200)).replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 13)).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .image(let data, _):
                        Text("图片").font(.system(size: 13, weight: .medium))
                        Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text(record.copiedAt, style: .time).font(.system(size: 10)).foregroundStyle(.tertiary)
                        if isCurrent {
                            Text("当前")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.10), in: Capsule())
                                .help("与系统剪贴板当前内容一致")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10).frame(height: 72)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(accessibilityTitle)
          .help("恢复到剪贴板")
          .interactiveCursor()
          Button(action: remove) {
              Image(systemName: "trash").font(.system(size: 12))
                  .frame(width: 28, height: 32).contentShape(Rectangle())
          }.buttonStyle(HoverButtonStyle(tint: .red, horizontalPadding: 0, verticalPadding: 0))
              .help("删除这条记录").accessibilityLabel("删除这条记录")
              .padding(.trailing, 6)
        }
        .background(hovering ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
    }

    private var accessibilityTitle: String {
        let prefix = isCurrent ? "当前剪贴板，" : ""
        switch record.content {
        case .text(let text): return "\(prefix)恢复文字：\(String(text.prefix(100)))"
        case .image: return "\(prefix)恢复图片到剪贴板"
        }
    }
}
