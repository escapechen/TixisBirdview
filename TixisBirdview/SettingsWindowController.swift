//
//  SettingsWindowController.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 22.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let monitor: FrigateMonitor
    private var window: NSWindow?

    init(monitor: FrigateMonitor) {
        self.monitor = monitor
    }

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(
            rootView: SettingsMenuView(monitor: monitor)
                .frame(width: 360)
        )

        let window = NSWindow(contentViewController: hostingController)
        window.title = "TixisBirdview Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()

        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
