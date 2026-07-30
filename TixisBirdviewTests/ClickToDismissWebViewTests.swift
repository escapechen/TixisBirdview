//
//  OverlayDismissPanelTests.swift
//  TixisBirdviewTests
//  Created by/with/for Marcel Kühn on 30.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import AppKit
import XCTest
@testable import TixisBirdview

@MainActor
final class OverlayDismissPanelTests: XCTestCase {
    func testPrimaryClickDismissesTheOverlay() {
        let panel = makePanel()
        var dismissalCount = 0
        panel.onPrimaryClick = { dismissalCount += 1 }

        sendPrimaryClick(to: panel, at: NSPoint(x: 40, y: 40))

        XCTAssertEqual(dismissalCount, 1)
    }

    func testClickingAnOverlayControlDoesNotDismissTheOverlay() {
        let panel = makePanel()
        let button = NSButton(frame: NSRect(x: 20, y: 20, width: 28, height: 28))
        panel.contentView?.addSubview(button)
        var dismissalCount = 0
        panel.onPrimaryClick = { dismissalCount += 1 }

        sendPrimaryClick(to: panel, at: NSPoint(x: 30, y: 30))

        XCTAssertEqual(dismissalCount, 0)
    }

    func testDraggingDoesNotDismissTheOverlay() {
        let panel = makePanel()
        var dismissalCount = 0
        panel.onPrimaryClick = { dismissalCount += 1 }

        panel.sendEvent(mouseEvent(type: .leftMouseDown, location: NSPoint(x: 20, y: 20), in: panel))
        panel.sendEvent(mouseEvent(type: .leftMouseDragged, location: NSPoint(x: 40, y: 40), in: panel))
        panel.sendEvent(mouseEvent(type: .leftMouseUp, location: NSPoint(x: 40, y: 40), in: panel))

        XCTAssertEqual(dismissalCount, 0)
    }

    private func makePanel() -> OverlayDismissPanel {
        let panel = OverlayDismissPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSView(frame: panel.contentView?.bounds ?? .zero)
        return panel
    }

    private func sendPrimaryClick(to panel: OverlayDismissPanel, at location: NSPoint) {
        panel.sendEvent(mouseEvent(type: .leftMouseDown, location: location, in: panel))
        panel.sendEvent(mouseEvent(type: .leftMouseUp, location: location, in: panel))
    }

    private func mouseEvent(type: NSEvent.EventType, location: NSPoint, in panel: NSPanel) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            fatalError("Could not construct a mouse event for this test.")
        }

        return event
    }
}

@MainActor
final class LiveStreamRoutingTests: XCTestCase {
    func testResolvedStreamNameRestartsTheLivePlayer() {
        let monitor = FrigateMonitor()
        let initialSessionID = monitor.streamSessionID

        monitor.applyLiveStreamNames(["birdseye": "go2rtc_birdseye"])

        XCTAssertEqual(monitor.currentFeedStreamName, "go2rtc_birdseye")
        XCTAssertNotEqual(monitor.streamSessionID, initialSessionID)
    }

    func testUnchangedStreamNameDoesNotRestartTheLivePlayer() {
        let monitor = FrigateMonitor()
        let initialSessionID = monitor.streamSessionID

        monitor.applyLiveStreamNames(["birdseye": "birdseye"])

        XCTAssertEqual(monitor.streamSessionID, initialSessionID)
    }
}
