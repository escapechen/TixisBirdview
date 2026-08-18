//
//  ApplicationActivationController.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 18.08.26 with the help of Codex (GPT-5.6 Terra Extra High).
//

import AppKit

@MainActor
final class ApplicationActivationController {
    static let dockIconPreferenceKey = "showDockIcon"

    private let setActivationPolicy: @MainActor (NSApplication.ActivationPolicy) -> Void
    private let activateApplication: @MainActor () -> Void
    private var visibleUtilityWindowIDs = Set<String>()
    private(set) var showsDockIcon: Bool

    init(
        userDefaults: UserDefaults = .standard,
        setActivationPolicy: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = {
            _ = NSApp.setActivationPolicy($0)
        },
        activateApplication: @escaping @MainActor () -> Void = {
            NSApp.activate(ignoringOtherApps: true)
        }
    ) {
        self.setActivationPolicy = setActivationPolicy
        self.activateApplication = activateApplication
        showsDockIcon = userDefaults.object(forKey: Self.dockIconPreferenceKey) == nil
            ? true
            : userDefaults.bool(forKey: Self.dockIconPreferenceKey)
    }

    func applyCurrentPolicy() {
        refreshPolicy(activateIfRegular: false)
    }

    func updateDockIconVisibility(_ isVisible: Bool) {
        showsDockIcon = isVisible
        refreshPolicy(activateIfRegular: isVisible)
    }

    func updateUtilityWindow(_ identifier: String, isVisible: Bool) {
        if isVisible {
            visibleUtilityWindowIDs.insert(identifier)
        } else {
            visibleUtilityWindowIDs.remove(identifier)
        }
        refreshPolicy(activateIfRegular: isVisible)
    }

    var desiredPolicy: NSApplication.ActivationPolicy {
        showsDockIcon || !visibleUtilityWindowIDs.isEmpty ? .regular : .accessory
    }

    private func refreshPolicy(activateIfRegular: Bool) {
        let policy = desiredPolicy
        setActivationPolicy(policy)
        if activateIfRegular, policy == .regular {
            activateApplication()
        }
    }
}
