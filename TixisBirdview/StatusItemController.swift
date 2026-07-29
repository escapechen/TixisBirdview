//
//  StatusItemController.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 22.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let monitor: FrigateMonitor
    private let onOpenSettings: () -> Void
    private let onOpenAbout: () -> Void
    private let onDockIconPreferenceChanged: (Bool) -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let connectionNoticePanel = makeConnectionNoticePanel()
    private static let dockIconPreferenceKey = "showDockIcon"
    private var lastConnectionState: FrigateMonitor.ConnectionState?
    private var connectionDismissalTask: Task<Void, Never>?

    init(
        monitor: FrigateMonitor,
        onOpenSettings: @escaping () -> Void,
        onOpenAbout: @escaping () -> Void,
        onDockIconPreferenceChanged: @escaping (Bool) -> Void
    ) {
        self.monitor = monitor
        self.onOpenSettings = onOpenSettings
        self.onOpenAbout = onOpenAbout
        self.onDockIconPreferenceChanged = onDockIconPreferenceChanged
        super.init()

        menu.delegate = self
        statusItem.menu = menu
        statusItem.isVisible = true

        if let button = statusItem.button {
            button.title = ""
            button.toolTip = "TixisBirdview"
        }

        updateIcon(for: monitor.connectionState)
        rebuildMenu()
    }

    func updateIcon(for connectionState: FrigateMonitor.ConnectionState) {
        guard let button = statusItem.button else {
            return
        }

        let image = NSImage(named: "TixiMenuBar")
            ?? NSImage(systemSymbolName: connectionState.statusItemSystemImage, accessibilityDescription: "TixisBirdview")
            ?? NSImage(systemSymbolName: "video.fill", accessibilityDescription: "TixisBirdview")

        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        button.contentTintColor = connectionState.isFailure ? .systemRed : nil
        button.image = image
        button.title = ""
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("TixisBirdview: \(connectionState.title)")

        notifyConnectionTransition(to: connectionState)
    }

    func showMenu() {
        rebuildMenu()

        guard let button = statusItem.button else {
            return
        }

        button.performClick(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let titleItem = NSMenuItem(title: "TixisBirdview", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let statusItem = NSMenuItem(title: "Status: \(monitor.connectionState.title)", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        let eventItem = NSMenuItem(title: "Last: \(monitor.lastEventDescription)", action: nil, keyEquivalent: "")
        eventItem.isEnabled = false
        menu.addItem(eventItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About TixisBirdview", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let serverItem = NSMenuItem(title: "Server: \(monitor.serverAddress)", action: nil, keyEquivalent: "")
        serverItem.isEnabled = false
        menu.addItem(serverItem)

        let durationItem = NSMenuItem(title: "Keep Feed Open", action: nil, keyEquivalent: "")
        durationItem.submenu = durationMenu()
        menu.addItem(durationItem)

        let dockIconItem = NSMenuItem(title: "Show Dock Icon", action: #selector(toggleDockIcon), keyEquivalent: "")
        dockIconItem.target = self
        dockIconItem.state = showsDockIcon ? .on : .off
        menu.addItem(dockIconItem)

        menu.addItem(.separator())

        let monitoringItem = NSMenuItem(
            title: monitor.isMonitoring ? "Pause Monitoring" : "Start Monitoring",
            action: #selector(toggleMonitoring),
            keyEquivalent: ""
        )
        monitoringItem.target = self
        menu.addItem(monitoringItem)

        let showFeedItem = NSMenuItem(title: "Show Feed", action: #selector(showFeed), keyEquivalent: "")
        showFeedItem.target = self
        menu.addItem(showFeedItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit TixisBirdview", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func durationMenu() -> NSMenu {
        let menu = NSMenu()
        for seconds in [5, 10, 20, 30, 60, 120] {
            let item = NSMenuItem(title: "\(seconds) seconds", action: #selector(setOverlayDuration(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = Double(seconds)
            item.state = Int(monitor.overlayDurationSeconds) == seconds ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openSettings() {
        DispatchQueue.main.async { [weak self] in
            self?.onOpenSettings()
        }
    }

    @objc private func openAbout() {
        DispatchQueue.main.async { [weak self] in
            self?.onOpenAbout()
        }
    }

    @objc private func setOverlayDuration(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? Double else {
            return
        }

        monitor.overlayDurationSeconds = duration
        rebuildMenu()
    }

    @objc private func toggleDockIcon() {
        let newValue = !showsDockIcon
        UserDefaults.standard.set(newValue, forKey: Self.dockIconPreferenceKey)
        onDockIconPreferenceChanged(newValue)
        rebuildMenu()
    }

    @objc private func toggleMonitoring() {
        monitor.toggleMonitoring()
        rebuildMenu()
    }

    @objc private func showFeed() {
        monitor.showOverlayForLatestEvent()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private var showsDockIcon: Bool {
        UserDefaults.standard.object(forKey: Self.dockIconPreferenceKey) as? Bool ?? true
    }

    private func notifyConnectionTransition(to newState: FrigateMonitor.ConnectionState) {
        defer { lastConnectionState = newState }

        let wasFailed = lastConnectionState?.isFailure ?? false
        if newState.isFailure, !wasFailed {
            showConnectionNotice(
                title: "Connection lost",
                message: newState.title,
                systemImage: "wifi.exclamationmark",
                tint: .red
            )
        } else if wasFailed, !newState.isFailure, case .connected = newState {
            showConnectionNotice(
                title: "Connection restored",
                message: monitor.serverAddress,
                systemImage: "wifi",
                tint: .green
            )
        }
    }

    private func showConnectionNotice(
        title: String,
        message: String,
        systemImage: String,
        tint: Color
    ) {
        connectionDismissalTask?.cancel()
        connectionNoticePanel.orderOut(nil)
        connectionNoticePanel.contentViewController = NSHostingController(
            rootView: ConnectionNoticeView(
                title: title,
                message: message,
                systemImage: systemImage,
                tint: tint
            )
        )
        connectionNoticePanel.setContentSize(NSSize(width: 284, height: 88))

        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            let noticeFrame = connectionNoticePanel.frame
            connectionNoticePanel.setFrameOrigin(
                NSPoint(
                    x: visibleFrame.maxX - noticeFrame.width - 16,
                    y: visibleFrame.maxY - noticeFrame.height - 16
                )
            )
        }
        connectionNoticePanel.orderFrontRegardless()

        connectionDismissalTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }

            self?.connectionNoticePanel.orderOut(nil)
        }
    }

    private static func makeConnectionNoticePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 284, height: 88),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        return panel
    }
}

private extension FrigateMonitor.ConnectionState {
    var statusItemSystemImage: String {
        switch self {
        case .idle:
            "video"
        case .connecting:
            "arrow.triangle.2.circlepath"
        case .connected:
            "video.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }
}

private struct ConnectionNoticeView: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .font(.title3)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(width: 260, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}
