//
//  AboutWindowController.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 22.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import AppKit
import SwiftUI

@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "About TixisBirdview"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()

        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

private struct AboutView: View {
    private static let repositoryURL = URL(string: "https://github.com/escapechen/TixisBirdview")!
    private static let changelogURL = repositoryURL.appending(path: "blob/main/CHANGELOG.md")
    private static let licenseURL = repositoryURL.appending(path: "blob/main/LICENSE")
    private static let frigateURL = URL(string: "https://frigate.video")!

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("TixisBirdview")
                    .font(.title2.weight(.semibold))

                Text("Version \(AppVersionInfo.displayVersion) (\(AppVersionInfo.displayBuild))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("A small macOS bird activity companion compatible with Frigate.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(spacing: 8) {
                Link("TixisBirdview on GitHub", destination: Self.repositoryURL)
                Link("View changelog", destination: Self.changelogURL)
            }
            .font(.callout)

            VStack(spacing: 4) {
                Text("Built by Marcel Kühn with OpenAI Codex")
                Text("GPT-5.6 Terra · Extra High reasoning")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
            .multilineTextAlignment(.center)

            HStack(spacing: 0) {
                Text("With thanks to ")
                Link("Frigate", destination: Self.frigateURL)
                Text(" and its open-source community.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                Text("Released under the ")
                Link("MIT License", destination: Self.licenseURL)
                Text(".")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 400)
    }
}
