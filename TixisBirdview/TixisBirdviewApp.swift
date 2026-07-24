//
//  TixisBirdviewApp.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 22.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import AppKit

@main
enum TixisBirdviewMain {
    private static let dockIconPreferenceKey = "showDockIcon"
    private static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(UserDefaults.standard.object(forKey: dockIconPreferenceKey) as? Bool == false ? .accessory : .regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: FrigateMonitor?
    private var overlayController: OverlayWindowController?
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindowController: AboutWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppVersionInfo.incrementRunBuildNumber()

        let monitor = FrigateMonitor()
        let overlayController = OverlayWindowController()
        let settingsWindowController = SettingsWindowController(monitor: monitor)
        let aboutWindowController = AboutWindowController()
        configureAppIcon()
        configureMainMenu(
            settingsWindowController: settingsWindowController,
            aboutWindowController: aboutWindowController
        )
        let statusItemController = StatusItemController(
            monitor: monitor,
            onOpenSettings: { [settingsWindowController] in
                settingsWindowController.show()
            },
            onOpenAbout: { [aboutWindowController] in
                aboutWindowController.show()
            },
            onDockIconPreferenceChanged: { showDockIcon in
                NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
                if showDockIcon {
                    NSApp.activate()
                }
            }
        )

        overlayController.configure(with: monitor)

        monitor.onOverlayVisibilityChanged = { [overlayController] shouldShowOverlay in
            if shouldShowOverlay {
                overlayController.show()
            } else {
                overlayController.hide()
            }
        }

        monitor.onConnectionStateChanged = { [statusItemController] connectionState in
            statusItemController.updateIcon(for: connectionState)
        }

        monitor.start()

        self.monitor = monitor
        self.overlayController = overlayController
        self.statusItemController = statusItemController
        self.settingsWindowController = settingsWindowController
        self.aboutWindowController = aboutWindowController
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate()
        settingsWindowController?.show()
        return false
    }

    private func configureAppIcon() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let iconImage = NSImage(contentsOf: iconURL) else {
            return
        }

        NSApp.applicationIconImage = iconImage
    }

    private func configureMainMenu(
        settingsWindowController: SettingsWindowController,
        aboutWindowController: AboutWindowController
    ) {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(
            NSMenuItem(
                title: "About TixisBirdview",
                action: #selector(showAbout),
                keyEquivalent: ""
            )
        )
        appMenu.addItem(
            NSMenuItem(
                title: "Settings...",
                action: #selector(showSettings),
                keyEquivalent: ","
            )
        )
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit TixisBirdview",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        appMenu.items
            .filter { $0.action != #selector(NSApplication.terminate(_:)) }
            .forEach { $0.target = self }
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func showSettings() {
        settingsWindowController?.show()
    }

    @objc private func showAbout() {
        aboutWindowController?.show()
    }
}
