//
//  AboutWindowController.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 22.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import AppKit
import SwiftUI

@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let onWindowVisibilityChanged: (Bool) -> Void

    init(onWindowVisibilityChanged: @escaping (Bool) -> Void = { _ in }) {
        self.onWindowVisibilityChanged = onWindowVisibilityChanged
    }

    func show() {
        if let window {
            if !window.isVisible {
                onWindowVisibilityChanged(true)
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "About TixisBirdview"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        self.window = window

        onWindowVisibilityChanged(true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onWindowVisibilityChanged(false)
    }
}

private struct AboutView: View {
    private static let repositoryURL = URL(string: "https://github.com/escapechen/TixisBirdview")!
    private static let changelogURL = repositoryURL.appending(path: "blob/main/CHANGELOG.md")
    private static let licenseURL = repositoryURL.appending(path: "blob/main/LICENSE")
    private static let privacyURL = repositoryURL.appending(path: "blob/main/PRIVACY.md")
    private static let frigateURL = URL(string: "https://frigate.video")!

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityLabel("TixisBirdview icon")

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
                Link("View Changelog", destination: Self.changelogURL)
                Link("Privacy", destination: Self.privacyURL)
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
