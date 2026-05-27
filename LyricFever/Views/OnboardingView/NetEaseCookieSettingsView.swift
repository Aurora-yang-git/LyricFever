//
//  NetEaseCookieSettingsView.swift
//  Lyric Fever
//
// Settings tab for mainland China users: paste personal NetEase cookies
// so the app bypasses the Vercel proxy and calls music.163.com/api/ directly.

import SwiftUI

struct NetEaseCookieSettingsView: View {
    @AppStorage("neteaseMusicU") var musicU: String = ""
    @AppStorage("neteaseCsrf") var csrf: String = ""

    var isActive: Bool { !musicU.isEmpty && !csrf.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("NetEase 直连（中国大陆）")
                .font(.system(size: 15, weight: .bold))

            Text("默认的 NetEase API 部署在 Vercel，大陆网络无法访问。填入自己网易云账号的 Cookie，App 会直接调用 music.163.com 的接口，无需任何服务器。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("如何获取 Cookie")
                .font(.subheadline).bold()
            Text("1. 用 Safari 打开 music.163.com 并登录\n2. 按 Option+Cmd+I 打开开发者工具\n3. 切到「存储」→「Cookie」→「music.163.com」\n4. 找到 MUSIC_U 和 __csrf，分别复制其「值」粘贴到下方")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("MUSIC_U")
                        .frame(width: 80, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                    SecureField("粘贴 MUSIC_U 的值", text: $musicU)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("__csrf")
                        .frame(width: 80, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                    TextField("粘贴 __csrf 的值", text: $csrf)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if isActive {
                Label("直连模式已启用，重启 App 后生效", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Label("当前使用 Vercel 代理（默认）", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Button("清除 Cookie") {
                musicU = ""
                csrf = ""
            }
            .disabled(!isActive)

            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
