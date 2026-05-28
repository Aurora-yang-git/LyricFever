//
//  NetEaseCookieSettingsView.swift
//  Lyric Fever

import SwiftUI

struct NetEaseCookieSettingsView: View {
    @AppStorage("neteaseMusicU") var musicU: String = ""
    @AppStorage("neteaseCsrf") var csrf: String = ""

    var isActive: Bool { !musicU.isEmpty && !csrf.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepView(
                title: "NetEase Direct (Mainland China)",
                description: "The default NetEase API is hosted on Vercel, which is blocked in mainland China. Paste your NetEase cookies below to connect directly to music.163.com — no server needed."
            )

            Picker("", selection: .constant(0)) {
                Text("Cookie Login").tag(0)
            }
            .pickerStyle(.segmented)
            .disabled(true)

            VStack(alignment: .leading, spacing: 12) {
                Text("How to get your cookies")
                    .font(.headline)

                Text("1. Open music.163.com in Safari and log in\n2. Press Option+Cmd+I to open Developer Tools\n3. Go to Storage → Cookies → music.163.com\n4. Copy the Value of MUSIC_U and __csrf below")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("MUSIC_U")
                            .frame(width: 80, alignment: .trailing)
                            .font(.system(.body, design: .monospaced))
                        SecureField("Paste MUSIC_U value", text: $musicU)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("__csrf")
                            .frame(width: 80, alignment: .trailing)
                            .font(.system(.body, design: .monospaced))
                        TextField("Paste __csrf value", text: $csrf)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if isActive {
                    Label("Direct mode enabled — restart the app to apply", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                } else {
                    Label("Using Vercel proxy (default)", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }

            HStack {
                Button("Clear Cookies") {
                    musicU = ""
                    csrf = ""
                }
                .disabled(!isActive)
                Spacer()
            }
            .padding(.vertical, 15)
        }
        .padding(.horizontal, 20)
    }
}
