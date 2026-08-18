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
    private var updateChecker: UpdateChecker?
    private var activationController: ApplicationActivationController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let monitor = FrigateMonitor()
        let overlayController = OverlayWindowController()
        let updateChecker = UpdateChecker()
        let activationController = ApplicationActivationController()
        let applyDockIconPreference: (Bool) -> Void = { showDockIcon in
            activationController.updateDockIconVisibility(showDockIcon)
        }
        let settingsWindowController = SettingsWindowController(
            monitor: monitor,
            updateChecker: updateChecker,
            onDockIconPreferenceChanged: applyDockIconPreference,
            onWindowVisibilityChanged: {
                activationController.updateUtilityWindow("settings", isVisible: $0)
            }
        )
        let aboutWindowController = AboutWindowController(
            onWindowVisibilityChanged: {
                activationController.updateUtilityWindow("about", isVisible: $0)
            }
        )
        self.updateChecker = updateChecker
        self.activationController = activationController
        activationController.applyCurrentPolicy()
        configureAppIcon()
        configureMainMenu(
            settingsWindowController: settingsWindowController,
            aboutWindowController: aboutWindowController,
            updateChecker: updateChecker
        )
        let statusItemController = StatusItemController(
            monitor: monitor,
            updateChecker: updateChecker,
            onOpenSettings: { [settingsWindowController] in
                settingsWindowController.show()
            },
            onOpenAbout: { [aboutWindowController] in
                aboutWindowController.show()
            },
            onDockIconPreferenceChanged: applyDockIconPreference
        )
        updateChecker.onUpdateAvailable = { [weak statusItemController] release in
            statusItemController?.notifyUpdateAvailable(release)
        }

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
        updateChecker.performAutomaticCheckIfNeeded()

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

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        statusItemController?.makeDockMenu()
    }

    private func configureAppIcon() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let iconImage = NSImage(contentsOf: iconURL) else {
            return
        }

        NSApp.applicationIconImage = iconImage
    }

    func configureMainMenu(
        settingsWindowController: SettingsWindowController,
        aboutWindowController: AboutWindowController,
        updateChecker: UpdateChecker
    ) {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem(title: "TixisBirdview", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "TixisBirdview")

        appMenu.addItem(
            NSMenuItem(
                title: "About TixisBirdview",
                action: #selector(showAbout),
                keyEquivalent: ""
            )
        )
        appMenu.addItem(
            NSMenuItem(
                title: "Settings…",
                action: #selector(showSettings),
                keyEquivalent: ","
            )
        )
        appMenu.addItem(
            NSMenuItem(
                title: "Check for Updates…",
                action: #selector(checkForUpdates),
                keyEquivalent: ""
            )
        )
        appMenu.addItem(.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        appMenu.addItem(.separator())
        let hideItem = NSMenuItem(
            title: "Hide TixisBirdview",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.target = NSApp
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        showAllItem.target = NSApp
        appMenu.addItem(showAllItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit TixisBirdview",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        appMenu.items
            .filter {
                $0.action == #selector(showAbout)
                    || $0.action == #selector(showSettings)
                    || $0.action == #selector(checkForUpdates)
            }
            .forEach { $0.target = self }
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
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

    @objc private func checkForUpdates() {
        updateChecker?.checkAndPresentResult()
    }
}
