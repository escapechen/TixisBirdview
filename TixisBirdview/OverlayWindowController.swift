//
//  OverlayWindowController.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 22.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class OverlayWindowController: NSObject, NSWindowDelegate {
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private weak var monitor: FrigateMonitor?
    @ObservationIgnored private let legacyFrameAutosaveName = "TixisBirdviewFeedOverlayFrame"
    @ObservationIgnored private let originAutosaveName = "TixisBirdviewFeedOverlayOrigin"
    @ObservationIgnored private let widthAutosaveName = "TixisBirdviewFeedOverlayWidth"
    @ObservationIgnored private var contentAspectRatio: CGFloat = 16 / 9
    @ObservationIgnored private var isApplyingFrame = false

    private let defaultWidth: CGFloat = 360
    private let screenMargin: CGFloat = 18

    func configure(with monitor: FrigateMonitor) {
        self.monitor = monitor

        if panel == nil {
            makePanel()
        }
    }

    func show() {
        if panel == nil {
            makePanel()
        }

        guard let panel else {
            return
        }

        guard !panel.isVisible else {
            panel.orderFrontRegardless()
            return
        }

        restoreFrame(for: panel)

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }

        let finalFrame = panel.frame
        panel.setFrame(scaled(finalFrame, by: 0.96), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() {
        guard let monitor else {
            return
        }

        let panel = OverlayDismissPanel(
            contentRect: NSRect(x: 0, y: 0, width: defaultWidth, height: defaultWidth / contentAspectRatio),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentMinSize = NSSize(width: 180, height: 110)
        panel.contentAspectRatio = NSSize(width: contentAspectRatio, height: 1)
        panel.delegate = self
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.onPrimaryClick = { [weak monitor] in
            monitor?.dismissOverlay()
        }

        panel.contentView = NSHostingView(
            rootView: VideoFeedView(
                monitor: monitor,
                onAspectRatioChanged: { [weak self] aspectRatio in
                    self?.updateContentAspectRatio(aspectRatio)
                }
            )
        )

        self.panel = panel
        restoreFrame(for: panel)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingFrame else {
            return
        }

        saveGeometry()
    }

    func windowDidResize(_ notification: Notification) {
        guard !isApplyingFrame else {
            return
        }

        saveGeometry()
    }

    private func restoreFrame(for panel: NSPanel) {
        if let savedOrigin = savedOrigin(), let savedWidth = savedWidth() {
            setFrame(
                fittedFrame(
                    width: savedWidth,
                    aspectRatio: contentAspectRatio,
                    origin: savedOrigin,
                    in: visibleFrame(
                        for: NSRect(
                            x: savedOrigin.x,
                            y: savedOrigin.y,
                            width: savedWidth,
                            height: savedWidth / contentAspectRatio
                        )
                    )
                ),
                for: panel,
                display: false
            )
            return
        }

        migrateLegacyFrameIfNeeded()

        if let savedOrigin = savedOrigin(), let savedWidth = savedWidth() {
            setFrame(
                fittedFrame(
                    width: savedWidth,
                    aspectRatio: contentAspectRatio,
                    origin: savedOrigin,
                    in: visibleFrame(
                        for: NSRect(
                            x: savedOrigin.x,
                            y: savedOrigin.y,
                            width: savedWidth,
                            height: savedWidth / contentAspectRatio
                        )
                    )
                ),
                for: panel,
                display: false
            )
        } else {
            position(panel: panel)
        }
    }

    func updateContentAspectRatio(_ aspectRatio: CGFloat) {
        guard aspectRatio.isFinite,
              (0.25 ... 8).contains(aspectRatio),
              abs(aspectRatio - contentAspectRatio) > 0.01 else {
            return
        }

        contentAspectRatio = aspectRatio

        guard let panel else {
            return
        }

        panel.contentAspectRatio = NSSize(width: contentAspectRatio, height: 1)

        if savedOrigin() != nil, let savedWidth = savedWidth() {
            setFrame(
                fittedFrame(
                    width: savedWidth,
                    aspectRatio: contentAspectRatio,
                    origin: panel.frame.origin,
                    in: visibleFrame(for: panel.frame)
                ),
                for: panel,
                display: panel.isVisible
            )
        } else {
            position(panel: panel)
        }
    }

    private func saveGeometry() {
        guard let panel else {
            return
        }

        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: originAutosaveName)
        UserDefaults.standard.set(panel.frame.width, forKey: widthAutosaveName)
    }

    private func position(panel: NSPanel) {
        guard let screenFrame = NSScreen.main?.visibleFrame else {
            return
        }

        setFrame(defaultFrame(in: screenFrame), for: panel, display: false)
    }

    private func defaultFrame(in screenFrame: NSRect) -> NSRect {
        let availableFrame = availableFrame(in: screenFrame)
        let size = fittedSize(width: defaultWidth, aspectRatio: contentAspectRatio, in: availableFrame)
        return NSRect(
            x: availableFrame.maxX - size.width,
            y: availableFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func migrateLegacyFrameIfNeeded() {
        guard let legacyFrameString = UserDefaults.standard.string(forKey: legacyFrameAutosaveName) else {
            return
        }

        let legacyFrame = NSRectFromString(legacyFrameString)
        guard legacyFrame.width > 0, legacyFrame.height > 0 else {
            UserDefaults.standard.removeObject(forKey: legacyFrameAutosaveName)
            return
        }

        UserDefaults.standard.set(NSStringFromPoint(legacyFrame.origin), forKey: originAutosaveName)
        UserDefaults.standard.set(legacyFrame.width, forKey: widthAutosaveName)
        UserDefaults.standard.removeObject(forKey: legacyFrameAutosaveName)
    }

    private func savedOrigin() -> NSPoint? {
        guard let originString = UserDefaults.standard.string(forKey: originAutosaveName) else {
            return nil
        }

        return NSPointFromString(originString)
    }

    private func savedWidth() -> CGFloat? {
        let width = UserDefaults.standard.double(forKey: widthAutosaveName)
        return width > 0 ? width : nil
    }

    private func visibleFrame(for frame: NSRect) -> NSRect? {
        NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
    }

    private func availableFrame(in screenFrame: NSRect) -> NSRect {
        screenFrame.insetBy(dx: screenMargin, dy: screenMargin)
    }

    private func fittedFrame(width: CGFloat, aspectRatio: CGFloat, origin: NSPoint, in screenFrame: NSRect?) -> NSRect {
        guard let screenFrame else {
            return NSRect(x: origin.x, y: origin.y, width: width, height: width / aspectRatio)
        }

        let availableFrame = availableFrame(in: screenFrame)
        let size = fittedSize(width: width, aspectRatio: aspectRatio, in: availableFrame)
        let x = min(max(origin.x, availableFrame.minX), availableFrame.maxX - size.width)
        let y = min(max(origin.y, availableFrame.minY), availableFrame.maxY - size.height)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func fittedSize(width: CGFloat, aspectRatio: CGFloat, in availableFrame: NSRect) -> NSSize {
        let minimumWidth = min(180, availableFrame.width)
        let minimumHeight = min(110, availableFrame.height)
        var fittedWidth = min(max(width, minimumWidth), availableFrame.width)
        var fittedHeight = fittedWidth / aspectRatio

        if fittedHeight < minimumHeight {
            fittedWidth = min(max(fittedWidth, minimumHeight * aspectRatio), availableFrame.width)
            fittedHeight = fittedWidth / aspectRatio
        }

        if fittedHeight > availableFrame.height {
            fittedHeight = availableFrame.height
            fittedWidth = fittedHeight * aspectRatio
        }

        if fittedWidth > availableFrame.width {
            fittedWidth = availableFrame.width
            fittedHeight = fittedWidth / aspectRatio
        }

        return NSSize(width: fittedWidth, height: fittedHeight)
    }

    private func setFrame(_ frame: NSRect, for panel: NSPanel, display: Bool) {
        isApplyingFrame = true
        panel.setFrame(frame, display: display)
        isApplyingFrame = false
    }

    private func scaled(_ frame: NSRect, by factor: CGFloat) -> NSRect {
        let size = NSSize(width: frame.width * factor, height: frame.height * factor)
        return NSRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

final class OverlayDismissPanel: NSPanel {
    var onPrimaryClick: (() -> Void)?

    private var primaryMouseDownLocation: NSPoint?
    private var didDragPrimaryMouse = false
    private let clickMovementTolerance: CGFloat = 3

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            primaryMouseDownLocation = event.locationInWindow
            didDragPrimaryMouse = false

        case .leftMouseDragged:
            if let primaryMouseDownLocation,
               primaryMouseDownLocation.distance(to: event.locationInWindow) > clickMovementTolerance {
                didDragPrimaryMouse = true
            }

        case .leftMouseUp:
            let shouldDismiss = isPrimaryClick(event) && !isClickOnControl(event)
            primaryMouseDownLocation = nil
            didDragPrimaryMouse = false

            super.sendEvent(event)

            if shouldDismiss {
                onPrimaryClick?()
            }
            return

        default:
            break
        }

        super.sendEvent(event)
    }

    private func isPrimaryClick(_ event: NSEvent) -> Bool {
        guard event.buttonNumber == 0,
              primaryMouseDownLocation != nil,
              !didDragPrimaryMouse else {
            return false
        }

        return true
    }

    private func isClickOnControl(_ event: NSEvent) -> Bool {
        guard let contentView else {
            return false
        }

        let location = contentView.convert(event.locationInWindow, from: nil)
        var view = contentView.hitTest(location)

        while let currentView = view {
            if currentView is NSControl {
                return true
            }
            view = currentView.superview
        }

        return false
    }
}

private extension NSPoint {
    func distance(to other: NSPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
