//
//  SettingsWindowController.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 22.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSToolbarDelegate {
    private static let selectedPaneKey = "TixisBirdviewSelectedSettingsPane"
    private static let toolbarIdentifier = NSToolbar.Identifier("TixisBirdviewSettingsToolbar")

    private let monitor: FrigateMonitor
    private let paneSelection: SettingsPaneSelection
    private var window: NSWindow?
    private var toolbar: NSToolbar?

    init(monitor: FrigateMonitor) {
        self.monitor = monitor
        let savedPane = UserDefaults.standard.string(forKey: Self.selectedPaneKey)
            .flatMap(SettingsPane.init(rawValue:)) ?? .connection
        paneSelection = SettingsPaneSelection(selected: savedPane)
        super.init()
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            updateWindowTitle()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(
            rootView: SettingsMenuView(monitor: monitor, paneSelection: paneSelection)
                .frame(width: 560, height: 620)
        )

        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
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
        updateWindowTitle()
        window.makeKeyAndOrderFront(nil)
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
        window?.title = "TixisBirdview Settings — \(paneSelection.selected.title)"
    }
}

private extension SettingsPane {
    var toolbarItemIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(rawValue)
    }
}
