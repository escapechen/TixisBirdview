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

    func testOverlayCanNeverTakeKeyboardFocus() {
        let panel = makePanel()

        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
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
final class OverlayFramePersistenceGateTests: XCTestCase {
    func testProgrammaticFrameChangesNeverPersistGeometry() {
        let gate = OverlayFramePersistenceGate()

        gate.beginProgrammaticChange()

        XCTAssertFalse(gate.allowsPersistence)

        gate.endProgrammaticChange()

        XCTAssertTrue(gate.allowsPersistence)
    }

    func testNestedProgrammaticFrameChangesRemainSuppressedUntilTheAnimationFinishes() {
        let gate = OverlayFramePersistenceGate()

        gate.beginProgrammaticChange()
        gate.perform {}

        XCTAssertFalse(gate.allowsPersistence)

        gate.endProgrammaticChange()

        XCTAssertTrue(gate.allowsPersistence)
    }
}

@MainActor
final class FeedCameraSelectionTests: XCTestCase {
    func testReviewObjectNamesDeduplicateRepeatedVerifiedSubLabels() throws {
        let review = try JSONDecoder().decode(
            FrigateReviewItem.self,
            from: Data("""
            {
              "id": "garden-cat",
              "camera": "GARTEN_CAM",
              "start_time": 130,
              "end_time": 140,
              "severity": "alert",
              "data": {
                "objects": ["cat-verified"],
                "sub_labels": ["Tixi", "Tixi"]
              }
            }
            """.utf8)
        )

        XCTAssertEqual(review.data.objectNames, ["cat-verified", "Tixi"])
        XCTAssertEqual(review.data.bestObjectDescription, "Cat-Verified, Tixi")
    }

    func testCurrentFeedCameraPrefersNewerReviewActivity() throws {
        let monitor = FrigateMonitor()
        monitor.latestEvent = FrigateEvent(
            id: "older-event",
            camera: "FLUR_CAM",
            label: "cat",
            subLabel: nil,
            startTime: 100,
            endTime: 120,
            topScore: nil
        )
        monitor.latestReviewItem = try JSONDecoder().decode(
            FrigateReviewItem.self,
            from: Data("""
            {
              "id": "newer-review",
              "camera": "WZ_CAM",
              "start_time": 130,
              "end_time": 140,
              "severity": "alert",
              "data": { "objects": ["cat"], "sub_labels": [] }
            }
            """.utf8)
        )

        XCTAssertEqual(monitor.currentFeedCameraName, "WZ_CAM")
    }
}

@MainActor
final class LiveStreamRoutingTests: XCTestCase {
    func testResolvedStreamNameRestartsTheLivePlayer() {
        let monitor = FrigateMonitor()
        let initialSessionID = monitor.streamSessionID

        monitor.applyLiveStreamNames(["birdseye": "go2rtc_birdseye"])

        XCTAssertEqual(monitor.currentFeedStreamName, "go2rtc_birdseye")
        XCTAssertEqual(monitor.liveStreamRoutingStatus, .ready)
        XCTAssertNotEqual(monitor.streamSessionID, initialSessionID)
    }

    func testUnchangedStreamNameDoesNotRestartTheLivePlayer() {
        let monitor = FrigateMonitor()
        let initialSessionID = monitor.streamSessionID

        monitor.applyLiveStreamNames(["birdseye": "birdseye"])

        XCTAssertEqual(monitor.streamSessionID, initialSessionID)
    }

    func testUnmappedCameraNeverStartsMSEWithItsEventKey() {
        let monitor = FrigateMonitor()

        monitor.applyLiveStreamNames(["other_camera": "go2rtc_other_camera"])

        XCTAssertEqual(monitor.liveStreamRoutingStatus, .unavailable)
    }

    func testLiveRoutingAuthenticatesAndUsesTheFrigateConfiguredStream() async {
        let recorder = RequestRecorder()
        FrameRequestURLProtocol.handler = { request in
            recorder.requests.append(request)

            switch request.url?.path {
            case "/api/login":
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Set-Cookie": "frigate_token=fresh-session; Path=/; HttpOnly"]
                    )!,
                    Data()
                )
            case "/api/config":
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    Data("""
                    {"cameras":{"birdseye":{"live":{"streams":{"main":"go2rtc_birdseye"}}}}}
                    """.utf8)
                )
            default:
                XCTFail("Unexpected request: \(request.url?.path ?? "missing URL")")
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }
        }
        defer { FrameRequestURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FrameRequestURLProtocol.self]
        let monitor = FrigateMonitor(
            urlSession: URLSession(configuration: configuration),
            passwordProvider: { _ in "test-password" }
        )
        monitor.serverAddress = "https://frigate.example:8971"
        monitor.username = "test-user"

        await monitor.ensureLiveStreamNamesLoaded()

        XCTAssertEqual(monitor.currentFeedStreamName, "go2rtc_birdseye")
        XCTAssertEqual(monitor.liveStreamRoutingStatus, .ready)
        XCTAssertEqual(recorder.requests.map { $0.url?.path }, ["/api/login", "/api/config"])
    }
}

final class FrigateLoginContractTests: XCTestCase {
    func testLoginRequestUsesFrigateEndpointJSONAndCredentials() throws {
        let request = try FrigateLoginRequest.make(
            baseURL: URL(string: "https://frigate.example:8971")!,
            username: "birdy",
            password: "correct-horse"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://frigate.example:8971/api/login")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["user": "birdy", "password": "correct-horse"])
    }

    func testLoginResponseExtractsSessionCookie() throws {
        let loginURL = URL(string: "https://frigate.example:8971/api/login")!
        let response = try XCTUnwrap(HTTPURLResponse(
            url: loginURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Set-Cookie": "frigate_token=token-value; Path=/; HttpOnly"]
        ))

        let cookies = FrigateLoginRequest.sessionCookies(from: response, for: loginURL)

        XCTAssertEqual(cookies.count, 1)
        XCTAssertEqual(cookies.first?.name, "frigate_token")
        XCTAssertEqual(cookies.first?.value, "token-value")
    }
}

@MainActor
final class JpegFeedAuthenticationTests: XCTestCase {
    func testJpegFetchRefreshesAnExpiredSessionBeforeLoadingTheFrame() async throws {
        let recorder = RequestRecorder()
        FrameRequestURLProtocol.handler = { request in
            recorder.requests.append(request)

            switch request.url?.path {
            case "/api/login":
                XCTAssertEqual(request.httpMethod, "POST")
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Set-Cookie": "frigate_token=fresh-session; Path=/; HttpOnly"]
                    )!,
                    Data()
                )
            case "/api/birdseye/latest.jpg":
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "image/jpeg"]
                    )!,
                    Data([0xFF, 0xD8, 0xFF, 0xD9])
                )
            default:
                XCTFail("Unexpected request: \(request.url?.path ?? "missing URL")")
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }
        }
        defer { FrameRequestURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.protocolClasses = [FrameRequestURLProtocol.self]
        let monitor = FrigateMonitor(
            urlSession: URLSession(configuration: configuration),
            passwordProvider: { _ in "test-password" }
        )
        monitor.serverAddress = "https://frigate.example:8971"
        monitor.username = "test-user"

        let imageData = try await monitor.fetchLatestFrame()

        XCTAssertEqual(imageData, Data([0xFF, 0xD8, 0xFF, 0xD9]))
        XCTAssertEqual(recorder.requests.map { $0.url?.path }, ["/api/login", "/api/birdseye/latest.jpg"])
    }
}

private final class RequestRecorder: @unchecked Sendable {
    var requests: [URLRequest] = []
}

private final class FrameRequestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class MqttProtocolContractTests: XCTestCase {
    func testConnectPacketCarriesConfiguredCredentials() throws {
        let packet = try XCTUnwrap(MqttClient.makeConnectPacket(
            configuration: .init(
                host: "mqtt.example",
                port: 1883,
                useTLS: false,
                username: "frigate-client",
                password: "broker-secret",
                topicPrefix: "frigate"
            ),
            clientIdentifier: "tixisbirdview-test"
        ))

        XCTAssertEqual(packet.header, 0x10)
        var offset = 0
        XCTAssertEqual(readMqttString(packet.payload, offset: &offset), "MQTT")
        XCTAssertEqual(packet.payload[offset], 4)
        offset += 1
        XCTAssertEqual(packet.payload[offset], 0xc2, "clean session, username, password")
        offset += 3 // flags and 30-second keepalive
        XCTAssertEqual(readMqttString(packet.payload, offset: &offset), "tixisbirdview-test")
        XCTAssertEqual(readMqttString(packet.payload, offset: &offset), "frigate-client")
        XCTAssertEqual(readMqttString(packet.payload, offset: &offset), "broker-secret")
        XCTAssertEqual(offset, packet.payload.count)
    }

    func testSubscribePacketUsesBothFrigateEventTopics() throws {
        let packet = try XCTUnwrap(MqttClient.makeSubscriptionPacket(
            topicPrefix: "/frigate/",
            packetIdentifier: 42
        ))

        XCTAssertEqual(packet.header, 0x82)
        var offset = 0
        XCTAssertEqual(packet.payload[offset], 0)
        XCTAssertEqual(packet.payload[offset + 1], 42)
        offset += 2
        XCTAssertEqual(readMqttString(packet.payload, offset: &offset), "frigate/events")
        XCTAssertEqual(packet.payload[offset], 0)
        offset += 1
        XCTAssertEqual(readMqttString(packet.payload, offset: &offset), "frigate/reviews")
        XCTAssertEqual(packet.payload[offset], 0)
        offset += 1
        XCTAssertEqual(offset, packet.payload.count)
    }

    private func readMqttString(_ bytes: [UInt8], offset: inout Int) -> String? {
        guard offset + 2 <= bytes.count else { return nil }
        let length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        offset += 2
        guard offset + length <= bytes.count else { return nil }
        defer { offset += length }
        return String(bytes: bytes[offset..<(offset + length)], encoding: .utf8)
    }
}

@MainActor
final class MqttEventToOverlayTests: XCTestCase {
    func testRecentMqttEventPresentsTheMatchingCameraOverlay() {
        let monitor = FrigateMonitor()
        monitor.isMonitoring = true
        monitor.eventDeliveryMode = .mqtt
        monitor.mqttTopicPrefix = "frigate"
        monitor.popupTrigger = .anyObject
        monitor.isPopupCooldownEnabled = false
        monitor.isSoundAlertEnabled = false

        let payload = Data("""
        {"after":{"id":"event-123","camera":"kitchen_cam","label":"person","sub_label":"Tixi","start_time":\(Date().timeIntervalSince1970),"end_time":null,"top_score":0.95}}
        """.utf8)

        monitor.receiveMqttMessage(topic: "frigate/events", payload: payload)

        XCTAssertEqual(monitor.latestEvent?.camera, "kitchen_cam")
        XCTAssertEqual(monitor.overlayActivity?.camera, "kitchen_cam")
        XCTAssertEqual(monitor.overlayActivity?.title, "Tixi")
        XCTAssertTrue(monitor.shouldShowOverlay)

        monitor.dismissOverlay()
    }

    func testWrongMqttTopicDoesNotPresentAnOverlay() {
        let monitor = FrigateMonitor()
        monitor.isMonitoring = true
        monitor.eventDeliveryMode = .mqtt
        monitor.mqttTopicPrefix = "frigate"
        monitor.popupTrigger = .anyObject

        monitor.receiveMqttMessage(topic: "other/events", payload: Data("{}".utf8))

        XCTAssertNil(monitor.latestEvent)
        XCTAssertFalse(monitor.shouldShowOverlay)
    }
}

final class FeedPlaybackStateTests: XCTestCase {
    func testLiveStatusNoticeClearsTheFeedControls() {
        XCTAssertGreaterThan(
            FeedOverlayLayout.statusNoticeBottomInset,
            FeedOverlayLayout.controlsBottomInset + FeedOverlayLayout.controlsHeight
        )
    }

    func testLiveMSELatencyPolicyPrioritizesFreshFrames() {
        XCTAssertGreaterThanOrEqual(LiveStreamLatencyPolicy.retainedBufferedSeconds, 5)
        XCTAssertLessThan(LiveStreamLatencyPolicy.retainedBufferedSeconds, LiveStreamLatencyPolicy.maximumBufferedSeconds)
        XCTAssertGreaterThan(
            LiveStreamLatencyPolicy.maximumBufferedGapBeforeRecoverySeconds,
            LiveStreamLatencyPolicy.maximumBufferedSeconds
        )
        XCTAssertEqual(LiveStreamLatencyPolicy.maximumConsecutiveRecoveryAttempts, 3)
    }

    func testLiveMSEOnlyRecoversAfterExcessiveLag() {
        XCTAssertFalse(LiveStreamLatencyPolicy.shouldRecoverFromExcessiveLag(bufferedGap: 8))
        XCTAssertTrue(LiveStreamLatencyPolicy.shouldRecoverFromExcessiveLag(bufferedGap: 8.01))
    }

    func testMSEPlayerHTMLUsesVideoOnlyWithoutPlayheadManipulation() throws {
        let html = try XCTUnwrap(
            URL(string: "https://192.0.2.1:8971").map {
                FrigateMSEStreamView.html(
                    serverURL: $0,
                    cameraName: "GARTEN_CAM",
                    startupTimeoutSeconds: 5,
                    debugEnabled: false
                )
            }
        )

        XCTAssertFalse(html.contains("video.currentTime ="))
        XCTAssertFalse(html.contains("setLiveSeekableRange"))
        XCTAssertFalse(html.contains("video.playbackRate = playbackRate"))
        XCTAssertFalse(html.contains("mp4a.40.2"))
        XCTAssertFalse(html.contains("opus"))
        XCTAssertTrue(html.contains("const videoCodecs"))
        XCTAssertTrue(html.contains("const usingManagedMediaSource = !!window.ManagedMediaSource"))
        XCTAssertTrue(html.contains("if (usingManagedMediaSource)"))
        XCTAssertFalse(html.contains("window.ManagedMediaSource || window.MediaSource"))
        XCTAssertTrue(html.contains("video.addEventListener(\"playing\""))
        XCTAssertTrue(html.contains("ensurePlayback(\"pause\")"))
        XCTAssertTrue(html.contains("ensurePlayback(\"buffer update\")"))
        XCTAssertTrue(html.contains("gap <= 0.05"))
        XCTAssertTrue(html.contains("mediaSource.duration = Infinity"))
        XCTAssertFalse(html.contains("ensurePlayback(\"ended state\")"))
        XCTAssertTrue(html.contains("Live stream timeline reset while resuming playback."))
        XCTAssertTrue(html.contains("Live stream timeline moved backwards."))
        XCTAssertTrue(html.contains("gap > maximumBufferedGapBeforeRecoverySeconds"))
        XCTAssertTrue(html.contains("window.tixisBirdviewStop = stop"))
        XCTAssertTrue(html.contains("window.addEventListener(\"pagehide\", stop)"))
        XCTAssertTrue(html.contains("currentSocket.close()"))
        XCTAssertEqual(FrigateMSEStreamView.teardownJavaScript, "window.tixisBirdviewStop?.();")
        XCTAssertEqual(html.components(separatedBy: "connected();").count - 1, 1)
    }

    func testLiveMSEStartupWaitAllowsTheNextCameraKeyframe() {
        XCTAssertEqual(LiveStreamStartupPolicy.playableFrameWaitSeconds(configuredSeconds: 1), 15)
        XCTAssertEqual(LiveStreamStartupPolicy.playableFrameWaitSeconds(configuredSeconds: 5), 15)
        XCTAssertEqual(LiveStreamStartupPolicy.playableFrameWaitSeconds(configuredSeconds: 15), 15)
    }

    func testStreamStartsAsJPEGBeforeMSEBecomesPlayable() {
        let state = FeedPlaybackState.make(
            feedMode: .stream,
            isOverlayVisible: true,
            isUsingJPEGFallback: false,
            isLiveStreamReady: false,
            isLiveStreamRoutingReady: true
        )

        XCTAssertEqual(state, .jpegPreview)
        XCTAssertTrue(state.mountsMSEPlayer)
    }

    func testPlayableMSETransitionsToLiveVideo() {
        let state = FeedPlaybackState.make(
            feedMode: .stream,
            isOverlayVisible: true,
            isUsingJPEGFallback: false,
            isLiveStreamReady: true,
            isLiveStreamRoutingReady: true
        )

        XCTAssertEqual(state, .liveVideo)
        XCTAssertTrue(state.mountsMSEPlayer)
    }

    func testFallbackAndHiddenOverlayDoNotMountMSE() {
        let fallback = FeedPlaybackState.make(
            feedMode: .stream,
            isOverlayVisible: true,
            isUsingJPEGFallback: true,
            isLiveStreamReady: false,
            isLiveStreamRoutingReady: true
        )
        let hidden = FeedPlaybackState.make(
            feedMode: .stream,
            isOverlayVisible: false,
            isUsingJPEGFallback: false,
            isLiveStreamReady: false,
            isLiveStreamRoutingReady: true
        )

        XCTAssertEqual(fallback, .jpegSnapshots)
        XCTAssertFalse(fallback.mountsMSEPlayer)
        XCTAssertEqual(hidden, .jpegSnapshots)
        XCTAssertFalse(hidden.mountsMSEPlayer)
    }

    func testUnresolvedGo2RTCStreamKeepsTheFeedOnJPEG() {
        let state = FeedPlaybackState.make(
            feedMode: .stream,
            isOverlayVisible: true,
            isUsingJPEGFallback: false,
            isLiveStreamReady: false,
            isLiveStreamRoutingReady: false
        )

        XCTAssertEqual(state, .jpegSnapshots)
        XCTAssertFalse(state.mountsMSEPlayer)
    }
}

@MainActor
final class HIGInteractionTests: XCTestCase {
    func testApplicationMenuOffersStandardSettingsAndVisibilityCommands() throws {
        let delegate = AppDelegate()
        let monitor = FrigateMonitor()
        delegate.configureMainMenu(
            settingsWindowController: SettingsWindowController(monitor: monitor),
            aboutWindowController: AboutWindowController()
        )

        let appMenu = try XCTUnwrap(NSApp.mainMenu?.item(at: 0)?.submenu)
        let titles = appMenu.items.map(\.title)

        XCTAssertTrue(titles.contains("About TixisBirdview"))
        XCTAssertTrue(titles.contains("Settings..."))
        XCTAssertTrue(titles.contains("Hide TixisBirdview"))
        XCTAssertTrue(titles.contains("Hide Others"))
        XCTAssertTrue(titles.contains("Show All"))
        XCTAssertTrue(titles.contains("Quit TixisBirdview"))
    }

    func testVisibleCloseControlDismissesWithoutTakingFocus() {
        var dismissalCount = 0
        let button = WindowDismissButton.DismissView {
            dismissalCount += 1
        }

        button.performClick(nil)

        XCTAssertEqual(dismissalCount, 1)
        XCTAssertTrue(button.acceptsFirstMouse(for: nil))
    }

    func testSettingsPanesHaveStableNativeToolbarMetadata() {
        XCTAssertEqual(SettingsPane.allCases.map(\.rawValue), ["connection", "feedAndSound", "popupTriggers"])
        XCTAssertEqual(SettingsPane.connection.title, "Connection")
        XCTAssertEqual(SettingsPane.feedAndSound.title, "Feed & Sound")
        XCTAssertEqual(SettingsPane.popupTriggers.title, "Popup Triggers")
        XCTAssertEqual(SettingsPane.connection.systemImage, "network")
    }

    func testSettingsPaneSelectionUpdatesTheVisiblePane() {
        let selection = SettingsPaneSelection(selected: .connection)

        selection.selected = .popupTriggers

        XCTAssertEqual(selection.selected, .popupTriggers)
    }
}
