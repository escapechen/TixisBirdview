//
//  SettingsWindowController.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 22.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSToolbarDelegate, NSWindowDelegate {
    private static let selectedPaneKey = "TixisBirdviewSelectedSettingsPane"
    private static let toolbarIdentifier = NSToolbar.Identifier("TixisBirdviewSettingsToolbar")

    private let monitor: FrigateMonitor
    private let updateChecker: UpdateChecker
    private let onDockIconPreferenceChanged: (Bool) -> Void
    private let onWindowVisibilityChanged: (Bool) -> Void
    private let paneSelection: SettingsPaneSelection
    private var window: NSWindow?
    private var toolbar: NSToolbar?

    init(
        monitor: FrigateMonitor,
        updateChecker: UpdateChecker,
        onDockIconPreferenceChanged: @escaping (Bool) -> Void = { _ in },
        onWindowVisibilityChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.monitor = monitor
        self.updateChecker = updateChecker
        self.onDockIconPreferenceChanged = onDockIconPreferenceChanged
        self.onWindowVisibilityChanged = onWindowVisibilityChanged
        let savedPane = UserDefaults.standard.string(forKey: Self.selectedPaneKey)
            .flatMap(SettingsPane.init(rawValue:)) ?? .general
        paneSelection = SettingsPaneSelection(selected: savedPane)
        super.init()
    }

    func show() {
        if let window {
            if !window.isVisible {
                onWindowVisibilityChanged(true)
            }
            NSApp.activate(ignoringOtherApps: true)
            updateWindowTitle()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(
            rootView: SettingsMenuView(
                monitor: monitor,
                paneSelection: paneSelection,
                updateChecker: updateChecker,
                onDockIconPreferenceChanged: onDockIconPreferenceChanged
            )
                .frame(width: 560, height: 620)
        )

        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.toolbarStyle = .preference

        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = paneSelection.selected.toolbarItemIdentifier
        window.toolbar = toolbar

        self.window = window
        self.toolbar = toolbar
        onWindowVisibilityChanged(true)
        NSApp.activate(ignoringOtherApps: true)
        updateWindowTitle()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onWindowVisibilityChanged(false)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.toolbarItemIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.toolbarItemIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.toolbarItemIdentifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let pane = SettingsPane(rawValue: itemIdentifier.rawValue) else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.title
        item.paletteLabel = pane.title
        item.toolTip = "Show \(pane.title) settings"
        item.image = NSImage(systemSymbolName: pane.systemImage, accessibilityDescription: pane.title)
        item.target = self
        item.action = #selector(selectPane(_:))
        return item
    }

    @objc private func selectPane(_ sender: NSToolbarItem) {
        guard let pane = SettingsPane(rawValue: sender.itemIdentifier.rawValue) else {
            return
        }

        paneSelection.selected = pane
        UserDefaults.standard.set(pane.rawValue, forKey: Self.selectedPaneKey)
        toolbar?.selectedItemIdentifier = pane.toolbarItemIdentifier
        updateWindowTitle()
    }

    private func updateWindowTitle() {
        window?.title = paneSelection.selected.title
    }
}

private extension SettingsPane {
    var toolbarItemIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(rawValue)
    }
}
