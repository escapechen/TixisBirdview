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

        XCTAssertEqual(review.data.objectNames, ["cat", "Tixi"])
        XCTAssertEqual(review.data.bestObjectDescription, "Cat, Tixi")
    }

    func testCurrentFeedCameraPrefersNewerReviewActivity() throws {
        let monitor = FrigateMonitor()
        monitor.feedSource = .latestActivityCamera
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

    func testBirdseyeFeedSourceUsesTheServerComposite() {
        let monitor = FrigateMonitor()
        monitor.latestEvent = FrigateEvent(
            id: "latest-event",
            camera: "FLUR_CAM",
            label: "person",
            subLabel: nil,
            startTime: 200,
            endTime: nil,
            topScore: nil
        )
        monitor.feedSource = .frigateBirdseye
        monitor.applyLiveStreamNames(["birdseye": "birdseye"])

        XCTAssertEqual(monitor.currentFeedCameraName, "birdseye")
        XCTAssertEqual(monitor.currentFeedStreamName, "birdseye")
        XCTAssertEqual(monitor.feedURL.path, "/api/birdseye/latest.jpg")
        XCTAssertEqual(monitor.liveStreamRoutingStatus, .ready)
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
                    {"birdseye":{"enabled":true,"restream":true},"cameras":{"front_door":{"live":{"streams":{"main":"front_door_main"}}}}}
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
            passwordProvider: { _, _ in "test-password" }
        )
        monitor.serverAddress = "https://frigate.example:8971"
        monitor.username = "test-user"
        monitor.feedSource = .frigateBirdseye

        await monitor.ensureLiveStreamNamesLoaded()

        XCTAssertEqual(monitor.currentFeedStreamName, "birdseye")
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
            passwordProvider: { _, _ in "test-password" }
        )
        monitor.serverAddress = "https://frigate.example:8971"
        monitor.username = "test-user"

        let imageData = try await monitor.fetchLatestFrame()

        XCTAssertEqual(imageData, Data([0xFF, 0xD8, 0xFF, 0xD9]))
        XCTAssertEqual(recorder.requests.map { $0.url?.path }, ["/api/login", "/api/birdseye/latest.jpg"])
    }
}

@MainActor
final class ConnectionSecurityTests: XCTestCase {
    func testAddressWithoutSchemeDefaultsToHTTPS() throws {
        XCTAssertEqual(
            try FrigateMonitor.validatedServerAddress("frigate.example:8971"),
            "https://frigate.example:8971"
        )
    }

    func testChangingServerCannotReuseAnotherServersPassword() {
        let oldServer = "https://old-frigate.example:8971"
        let newServer = "https://new-frigate.example:8971"
        var requestedServer: String?
        var requestedUsername: String?
        let monitor = FrigateMonitor(passwordProvider: { serverAddress, username in
            requestedServer = serverAddress
            requestedUsername = username
            return serverAddress == oldServer ? "old-server-password" : nil
        })
        monitor.serverAddress = oldServer
        monitor.username = "birdy"

        let didApply = monitor.applyConnectionSettings(
            newServer,
            username: "birdy",
            password: ""
        )

        XCTAssertFalse(didApply)
        XCTAssertEqual(requestedServer, newServer)
        XCTAssertEqual(requestedUsername, "birdy")
        XCTAssertEqual(monitor.serverAddress, oldServer)
    }

    func testKeychainServiceIsScopedByServerOrigin() {
        XCTAssertNotEqual(
            FrigateMonitor.keychainServiceName(for: "https://first.example:8971"),
            FrigateMonitor.keychainServiceName(for: "https://second.example:8971")
        )
    }

    func testExplicitHTTPRequiresConfirmation() {
        let monitor = FrigateMonitor(passwordProvider: { _, _ in nil })

        XCTAssertFalse(monitor.applyConnectionSettings(
            "http://frigate.example:5000",
            username: "",
            password: ""
        ))
        XCTAssertTrue(monitor.serverAddressError?.contains("not encrypted") == true)

        XCTAssertTrue(monitor.applyConnectionSettings(
            "http://frigate.example:5000",
            username: "",
            password: "",
            allowInsecureTransport: true
        ))

        XCTAssertTrue(monitor.applyConnectionSettings(
            "https://frigate.invalid",
            username: "",
            password: ""
        ))
    }

    func testMqttWithoutTLSRequiresConfirmation() {
        let monitor = FrigateMonitor(passwordProvider: { _, _ in nil })

        XCTAssertFalse(monitor.applyMqttSettings(
            host: "mqtt.example",
            port: 1883,
            useTLS: false,
            username: "",
            password: "",
            topicPrefix: "frigate"
        ))
        XCTAssertTrue(monitor.mqttVerificationStatus?.contains("not encrypted") == true)

        XCTAssertTrue(monitor.applyMqttSettings(
            host: "mqtt.example",
            port: 1883,
            useTLS: false,
            username: "",
            password: "",
            topicPrefix: "frigate",
            allowInsecureTransport: true
        ))

        XCTAssertTrue(monitor.applyMqttSettings(
            host: "mqtt.example",
            port: 8883,
            useTLS: true,
            username: "",
            password: "",
            topicPrefix: "frigate"
        ))
    }

    func testRedirectPolicyAllowsOnlySameOrigin() throws {
        let source = try XCTUnwrap(URL(string: "https://frigate.example:8971/api/login"))

        XCTAssertTrue(SecureRedirectPolicy.allowsRedirect(
            from: source,
            to: try XCTUnwrap(URL(string: "https://frigate.example:8971/api/login/"))
        ))
        XCTAssertFalse(SecureRedirectPolicy.allowsRedirect(
            from: source,
            to: try XCTUnwrap(URL(string: "https://other.example:8971/api/login"))
        ))
        XCTAssertFalse(SecureRedirectPolicy.allowsRedirect(
            from: source,
            to: try XCTUnwrap(URL(string: "http://frigate.example:8971/api/login"))
        ))
    }

    func testLoginRedirectDelegateRejectsCrossOrigin307And308() throws {
        let source = try XCTUnwrap(URL(string: "https://frigate.example:8971/api/login"))
        let destination = try XCTUnwrap(URL(string: "https://other.example:8971/capture"))
        let task = URLSession.shared.dataTask(with: source)
        defer { task.cancel() }
        let delegate = SecureURLSessionDelegate()

        for statusCode in [307, 308] {
            let response = try XCTUnwrap(HTTPURLResponse(
                url: source,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": destination.absoluteString]
            ))
            var redirectedRequest: URLRequest?

            delegate.urlSession(
                .shared,
                task: task,
                willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: destination)
            ) { redirectedRequest = $0 }

            XCTAssertNil(redirectedRequest)
        }
    }

    func testAppDeclaresLocalNetworkPurpose() {
        let purpose = Bundle(for: AppDelegate.self)
            .object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String

        XCTAssertEqual(
            purpose,
            "TixisBirdview connects to the Frigate server and optional MQTT broker you configure on your local network."
        )
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
        let monitor = makeMonitor()

        let payload = Data("""
        {"after":{"id":"event-123","camera":"kitchen_cam","label":"person","sub_label":["Tixi",0.98],"start_time":\(Date().timeIntervalSince1970),"end_time":null,"top_score":0.95}}
        """.utf8)

        monitor.receiveMqttMessage(topic: "frigate/events", payload: payload)

        XCTAssertEqual(monitor.latestEvent?.camera, "kitchen_cam")
        XCTAssertEqual(monitor.overlayActivity?.camera, "kitchen_cam")
        XCTAssertEqual(monitor.overlayActivity?.title, "Tixi")
        XCTAssertTrue(monitor.shouldShowOverlay)

        monitor.dismissOverlay()
    }

    func testHttpStringSubLabelRemainsSupported() throws {
        let payload = Data("""
        {"id":"event-http","camera":"kitchen_cam","label":"cat","sub_label":"Bruno","start_time":\(Date().timeIntervalSince1970),"end_time":null,"top_score":0.95}
        """.utf8)

        let event = try JSONDecoder().decode(FrigateEvent.self, from: payload)

        XCTAssertEqual(event.subLabel, "Bruno")
        XCTAssertEqual(event.classificationNames, ["Bruno"])
    }

    func testLateEventSubLabelsAccumulateOnceDuringVisibleSession() throws {
        let monitor = makeMonitor()
        let startedAt = Date().timeIntervalSince1970

        monitor.receiveMqttMessage(
            topic: "frigate/events",
            payload: eventPayload(id: "cat-1", subLabel: nil, startedAt: startedAt)
        )

        XCTAssertEqual(monitor.overlayActivity?.title, "Cat")
        let presentationID = monitor.overlayPresentationID

        monitor.receiveMqttMessage(
            topic: "frigate/events",
            payload: eventPayload(id: "cat-1", subLabel: "Tixi", startedAt: startedAt)
        )
        monitor.receiveMqttMessage(
            topic: "frigate/events",
            payload: eventPayload(id: "cat-1", subLabel: "Tixi", startedAt: startedAt)
        )
        monitor.receiveMqttMessage(
            topic: "frigate/events",
            payload: eventPayload(id: "cat-2", subLabel: "Bruno", startedAt: startedAt + 1)
        )

        XCTAssertEqual(monitor.overlayActivity?.title, "Cat, Tixi, Bruno")
        XCTAssertEqual(monitor.overlayPresentationID, presentationID)
        XCTAssertTrue(monitor.shouldShowOverlay)
    }

    func testDifferentCameraRefreshesVisiblePopupWithoutReopeningIt() throws {
        let monitor = makeMonitor()
        monitor.feedSource = .latestActivityCamera
        let startedAt = Date().timeIntervalSince1970

        monitor.receiveMqttMessage(
            topic: "frigate/events",
            payload: eventPayload(
                id: "garden-event",
                camera: "garden_cam",
                subLabel: "Tixi",
                startedAt: startedAt
            )
        )
        let presentationID = monitor.overlayPresentationID
        let firstDismissalDate = try XCTUnwrap(monitor.overlayDismissalDate)

        monitor.receiveMqttMessage(
            topic: "frigate/events",
            payload: eventPayload(
                id: "kitchen-event",
                camera: "kitchen_cam",
                subLabel: "Bruno",
                startedAt: startedAt + 1
            )
        )

        XCTAssertEqual(monitor.overlayActivity?.camera, "kitchen_cam")
        XCTAssertEqual(monitor.overlayActivity?.title, "Bruno")
        XCTAssertEqual(monitor.currentFeedCameraName, "kitchen_cam")
        XCTAssertEqual(monitor.overlayPresentationID, presentationID)
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(monitor.overlayDismissalDate),
            firstDismissalDate
        )
    }

    func testPopupCooldownPreventsAVisibleFeedFromSwitchingCameras() {
        let monitor = makeMonitor()
        monitor.feedSource = .latestActivityCamera
        monitor.isPopupCooldownEnabled = true
        monitor.popupCooldownSeconds = 60
        let startedAt = Date().timeIntervalSince1970

        monitor.receiveMqttMessage(
            topic: "frigate/events",
            payload: eventPayload(
                id: "garden-event",
                camera: "garden_cam",
                subLabel: "Tixi",
                startedAt: startedAt
            )
        )
        monitor.receiveMqttMessage(
            topic: "frigate/events",
            payload: eventPayload(
                id: "kitchen-event",
                camera: "kitchen_cam",
                subLabel: "Bruno",
                startedAt: startedAt + 1
            )
        )

        XCTAssertEqual(monitor.latestEvent?.camera, "kitchen_cam")
        XCTAssertEqual(monitor.overlayActivity?.camera, "garden_cam")
        XCTAssertEqual(monitor.currentFeedCameraName, "garden_cam")
    }

    func testBirdseyeSourceRemainsStableAcrossDifferentCameraEvents() {
        let monitor = makeMonitor()
        monitor.feedSource = .frigateBirdseye
        let startedAt = Date().timeIntervalSince1970

        monitor.receiveMqttMessage(
            topic: "frigate/events",
            payload: eventPayload(
                id: "garden-event",
                camera: "garden_cam",
                subLabel: "Tixi",
                startedAt: startedAt
            )
        )
        monitor.receiveMqttMessage(
            topic: "frigate/events",
            payload: eventPayload(
                id: "kitchen-event",
                camera: "kitchen_cam",
                subLabel: "Bruno",
                startedAt: startedAt + 1
            )
        )

        XCTAssertEqual(monitor.overlayActivity?.camera, "kitchen_cam")
        XCTAssertEqual(monitor.currentFeedCameraName, "birdseye")
    }

    func testDismissedOverlayStartsANewClassificationSession() {
        let monitor = makeMonitor()
        let startedAt = Date().timeIntervalSince1970

        monitor.receiveMqttMessage(
            topic: "frigate/events",
            payload: eventPayload(id: "cat-1", subLabel: "Tixi", startedAt: startedAt)
        )
        monitor.dismissOverlay()
        monitor.receiveMqttMessage(
            topic: "frigate/events",
            payload: eventPayload(id: "cat-2", subLabel: "Bruno", startedAt: startedAt + 1)
        )

        XCTAssertEqual(monitor.overlayActivity?.title, "Bruno")
        XCTAssertFalse(monitor.overlayActivity?.classificationNames.contains("Tixi") ?? true)
    }

    func testLateReviewSubLabelsAccumulateWithoutRepeatingNames() {
        let monitor = makeMonitor()
        let startedAt = Date().timeIntervalSince1970

        monitor.receiveMqttMessage(
            topic: "frigate/reviews",
            payload: reviewPayload(subLabels: [], startedAt: startedAt)
        )
        monitor.receiveMqttMessage(
            topic: "frigate/reviews",
            payload: reviewPayload(subLabels: ["Tixi", "Tixi", "Bruno"], startedAt: startedAt)
        )

        XCTAssertEqual(monitor.overlayActivity?.title, "Cat, Tixi, Bruno")
    }

    func testSelectedBaseLabelAcceptsVerifiedReviewWithLateSubLabel() {
        let monitor = makeMonitor()
        monitor.popupTrigger = .selectedClassifications
        monitor.selectedClassificationNames = ["cat"]
        let startedAt = Date().timeIntervalSince1970

        monitor.receiveMqttMessage(
            topic: "frigate/events",
            payload: eventPayload(id: "cat-1", subLabel: nil, startedAt: startedAt)
        )
        monitor.receiveMqttMessage(
            topic: "frigate/reviews",
            payload: reviewPayload(
                objects: ["cat-verified"],
                subLabels: ["Bruno"],
                startedAt: startedAt
            )
        )

        XCTAssertEqual(monitor.overlayActivity?.title, "Cat, Bruno")
    }

    func testWrongMqttTopicDoesNotPresentAnOverlay() {
        let monitor = makeMonitor()

        monitor.receiveMqttMessage(topic: "other/events", payload: Data("{}".utf8))

        XCTAssertNil(monitor.latestEvent)
        XCTAssertFalse(monitor.shouldShowOverlay)
    }

    private func makeMonitor() -> FrigateMonitor {
        let monitor = FrigateMonitor()
        monitor.isMonitoring = true
        monitor.eventDeliveryMode = .mqtt
        monitor.mqttTopicPrefix = "frigate"
        monitor.popupTrigger = .anyObject
        monitor.isPopupCooldownEnabled = false
        monitor.isSoundAlertEnabled = false
        return monitor
    }

    private func eventPayload(
        id: String,
        camera: String = "garden_cam",
        subLabel: String?,
        startedAt: TimeInterval
    ) -> Data {
        let encodedSubLabel = subLabel.map { "[\"\($0)\",0.93]" } ?? "null"
        return Data("""
        {"after":{"id":"\(id)","camera":"\(camera)","label":"cat","sub_label":\(encodedSubLabel),"start_time":\(startedAt),"end_time":null,"top_score":0.91}}
        """.utf8)
    }

    private func reviewPayload(
        objects: [String] = ["cat"],
        subLabels: [String],
        startedAt: TimeInterval
    ) -> Data {
        let encodedObjects = objects.map { "\"\($0)\"" }.joined(separator: ",")
        let encodedSubLabels = subLabels.map { "\"\($0)\"" }.joined(separator: ",")
        return Data("""
        {"after":{"id":"review-1","camera":"garden_cam","start_time":\(startedAt),"end_time":null,"severity":"alert","data":{"objects":[\(encodedObjects)],"sub_labels":[\(encodedSubLabels)]}}}
        """.utf8)
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
        XCTAssertLessThan(
            LiveStreamLatencyPolicy.targetLatencySeconds,
            LiveStreamLatencyPolicy.liveEdgeResyncThresholdSeconds
        )
        XCTAssertLessThan(
            LiveStreamLatencyPolicy.liveEdgeResyncThresholdSeconds,
            LiveStreamLatencyPolicy.maximumBufferedGapBeforeRecoverySeconds
        )
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

    func testLiveMSEOnlyResyncsAfterThresholdAndCooldown() {
        XCTAssertFalse(
            LiveStreamLatencyPolicy.shouldResyncWithLiveEdge(
                bufferedGap: 3,
                secondsSinceLastResync: 5
            )
        )
        XCTAssertFalse(
            LiveStreamLatencyPolicy.shouldResyncWithLiveEdge(
                bufferedGap: 3.01,
                secondsSinceLastResync: 4.99
            )
        )
        XCTAssertTrue(
            LiveStreamLatencyPolicy.shouldResyncWithLiveEdge(
                bufferedGap: 3.01,
                secondsSinceLastResync: 5
            )
        )
    }

    func testMSEPlayerHTMLUsesVideoOnlyAndBoundedLiveEdgeResync() throws {
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

        XCTAssertTrue(html.contains("function resyncWithLiveEdge(reason)"))
        XCTAssertTrue(html.contains("video.currentTime = target"))
        XCTAssertTrue(html.contains("now - lastLiveEdgeResyncAt < liveEdgeResyncCooldownMs"))
        XCTAssertTrue(html.contains("resyncWithLiveEdge(\"buffer update\")"))
        XCTAssertTrue(html.contains("resyncWithLiveEdge(\"latency check\")"))
        XCTAssertFalse(html.contains("setLiveSeekableRange"))
        XCTAssertFalse(html.contains("video.playbackRate = playbackRate"))
        XCTAssertTrue(html.contains("const videoCodecs"))
        XCTAssertTrue(html.contains("const standardCodecs = [...videoCodecs"))
        XCTAssertTrue(html.contains("\"mp4a.40.2\""))
        XCTAssertTrue(html.contains("\"opus\""))
        XCTAssertTrue(html.contains("useStandardCodecNegotiation ? standardCodecs : videoCodecs"))
        XCTAssertTrue(html.contains("receivedSegments <= 1 && !useStandardCodecNegotiation"))
        XCTAssertTrue(html.contains("configured go2rtc source delivered no media"))
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
        let updateChecker = UpdateChecker(releaseLoader: { nil })
        delegate.configureMainMenu(
            settingsWindowController: SettingsWindowController(
                monitor: monitor,
                updateChecker: updateChecker
            ),
            aboutWindowController: AboutWindowController(),
            updateChecker: updateChecker
        )

        let appMenu = try XCTUnwrap(NSApp.mainMenu?.item(at: 0)?.submenu)
        let titles = appMenu.items.map(\.title)

        XCTAssertTrue(titles.contains("About TixisBirdview"))
        XCTAssertTrue(titles.contains("Settings…"))
        XCTAssertTrue(titles.contains("Check for Updates…"))
        XCTAssertTrue(titles.contains("Services"))
        XCTAssertTrue(titles.contains("Hide TixisBirdview"))
        XCTAssertTrue(titles.contains("Hide Others"))
        XCTAssertTrue(titles.contains("Show All"))
        XCTAssertTrue(titles.contains("Quit TixisBirdview"))
    }

    func testDockMenuProvidesStatusAndOperationalCommands() throws {
        let monitor = FrigateMonitor()
        let updateChecker = UpdateChecker(releaseLoader: { nil })
        let controller = StatusItemController(
            monitor: monitor,
            updateChecker: updateChecker,
            onOpenSettings: {},
            onOpenAbout: {},
            onDockIconPreferenceChanged: { _ in },
            installsStatusItem: false
        )

        let dockMenu = controller.makeDockMenu()
        let titles = dockMenu.items.map(\.title)

        XCTAssertTrue(titles.contains(where: { $0.hasPrefix("Status: ") }))
        XCTAssertTrue(titles.contains(where: { $0.hasPrefix("Last: ") }))
        XCTAssertTrue(titles.contains(monitor.isMonitoring ? "Pause Monitoring" : "Start Monitoring"))
        XCTAssertTrue(titles.contains("Show Feed"))
        XCTAssertTrue(titles.contains("Keep Feed Open"))
        XCTAssertTrue(titles.contains("Settings…"))
        XCTAssertTrue(titles.contains("Check for Updates…"))
        XCTAssertTrue(titles.contains("About TixisBirdview"))
        XCTAssertFalse(titles.contains("Show Dock Icon"))
        XCTAssertFalse(titles.contains("Quit TixisBirdview"))

        let durationMenu = try XCTUnwrap(
            dockMenu.items.first(where: { $0.title == "Keep Feed Open" })?.submenu
        )
        XCTAssertEqual(durationMenu.items.count, 6)
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
        XCTAssertEqual(SettingsPane.allCases.map(\.rawValue), ["general", "connection", "feedAndSound", "popupTriggers"])
        XCTAssertEqual(SettingsPane.general.title, "General")
        XCTAssertEqual(SettingsPane.connection.title, "Connection")
        XCTAssertEqual(SettingsPane.feedAndSound.title, "Feed & Sound")
        XCTAssertEqual(SettingsPane.popupTriggers.title, "Popup Triggers")
        XCTAssertEqual(SettingsPane.general.systemImage, "gearshape")
        XCTAssertEqual(SettingsPane.connection.systemImage, "network")
    }

    func testSettingsPaneSelectionUpdatesTheVisiblePane() {
        let selection = SettingsPaneSelection(selected: .connection)

        selection.selected = .popupTriggers

        XCTAssertEqual(selection.selected, .popupTriggers)
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {
    func testSemanticVersionComparisonHandlesVPrefixAndMissingPatchComponent() {
        XCTAssertTrue(AppUpdatePolicy.isNewer(remoteVersion: "v1.2.0", than: "1.1"))
        XCTAssertFalse(AppUpdatePolicy.isNewer(remoteVersion: "v1.1.0", than: "1.1"))
        XCTAssertFalse(AppUpdatePolicy.isNewer(remoteVersion: "not-a-version", than: "1.1"))
    }

    func testAutomaticChecksRunAtMostOncePerDay() {
        let now = Date(timeIntervalSince1970: 2_000_000)

        XCTAssertTrue(AppUpdatePolicy.shouldCheckAutomatically(lastCheck: nil, now: now))
        XCTAssertFalse(
            AppUpdatePolicy.shouldCheckAutomatically(
                lastCheck: now.addingTimeInterval(-60 * 60),
                now: now
            )
        )
        XCTAssertTrue(
            AppUpdatePolicy.shouldCheckAutomatically(
                lastCheck: now.addingTimeInterval(-25 * 60 * 60),
                now: now
            )
        )
    }

    func testNewerPublishedReleaseBecomesAvailableWithoutDownloadingIt() async throws {
        let expectedRelease = PublishedAppRelease(
            version: "1.2.0",
            pageURL: try XCTUnwrap(URL(string: "https://github.com/escapechen/TixisBirdview/releases/tag/v1.2.0"))
        )
        let checker = UpdateChecker(
            currentVersion: "1.1",
            releaseLoader: { expectedRelease }
        )

        await checker.refresh(recordAutomaticCheck: false)

        XCTAssertEqual(checker.state, .updateAvailable(expectedRelease))
        XCTAssertEqual(checker.availableRelease, expectedRelease)
        XCTAssertEqual(checker.menuItemTitle, "Update to 1.2.0…")
    }

    func testAutomaticUpdateNotificationAppearsOnlyOncePerVersion() async throws {
        let suiteName = "UpdateCheckerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let release = PublishedAppRelease(
            version: "1.2.0",
            pageURL: try XCTUnwrap(URL(string: "https://github.com/escapechen/TixisBirdview/releases/tag/v1.2.0"))
        )
        let checker = UpdateChecker(
            defaults: defaults,
            currentVersion: "1.1",
            releaseLoader: { release }
        )
        var notifications = 0
        checker.onUpdateAvailable = { _ in notifications += 1 }

        await checker.refresh(recordAutomaticCheck: true)
        await checker.refresh(recordAutomaticCheck: true)

        XCTAssertEqual(notifications, 1)
    }

    func testMissingGitHubReleaseIsAValidEmptyState() async {
        let checker = UpdateChecker(
            currentVersion: "1.1",
            releaseLoader: { nil }
        )

        await checker.refresh(recordAutomaticCheck: false)

        XCTAssertEqual(checker.state, .noPublishedRelease)
        XCTAssertEqual(checker.statusText, "No published release is available yet.")
    }

    func testAboutBuildUsesTheSignedBundleBuildNumberOnly() {
        XCTAssertEqual(AppVersionInfo.displayBuild, AppVersionInfo.bundleBuildNumber)
    }
}

@MainActor
final class ApplicationActivationControllerTests: XCTestCase {
    func testAccessoryPolicyReturnsOnlyAfterLastUtilityWindowCloses() throws {
        let suiteName = "ApplicationActivationControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: ApplicationActivationController.dockIconPreferenceKey)
        var policies: [NSApplication.ActivationPolicy] = []

        let controller = ApplicationActivationController(
            userDefaults: defaults,
            setActivationPolicy: { policies.append($0) },
            activateApplication: {}
        )

        controller.applyCurrentPolicy()
        controller.updateUtilityWindow("settings", isVisible: true)
        controller.updateUtilityWindow("about", isVisible: true)
        controller.updateUtilityWindow("settings", isVisible: false)
        controller.updateUtilityWindow("about", isVisible: false)

        XCTAssertEqual(policies, [.accessory, .regular, .regular, .regular, .accessory])
    }

    func testDockIconKeepsRegularPolicyAfterUtilityWindowCloses() throws {
        let suiteName = "ApplicationActivationControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: ApplicationActivationController.dockIconPreferenceKey)

        let controller = ApplicationActivationController(
            userDefaults: defaults,
            setActivationPolicy: { _ in },
            activateApplication: {}
        )

        controller.updateUtilityWindow("settings", isVisible: true)
        controller.updateUtilityWindow("settings", isVisible: false)

        XCTAssertEqual(controller.desiredPolicy, .regular)
    }
}

final class RecentIdentifierCacheTests: XCTestCase {
    func testDuplicateIdentifierIsRejected() {
        var cache = RecentIdentifierCache(capacity: 3)

        XCTAssertTrue(cache.insert("one"))
        XCTAssertFalse(cache.insert("one"))
        XCTAssertEqual(cache.count, 1)
    }

    func testOldestIdentifierIsEvictedAtCapacity() {
        var cache = RecentIdentifierCache(capacity: 3)

        cache.insert("one")
        cache.insert("two")
        cache.insert("three")
        cache.insert("four")

        XCTAssertEqual(cache.count, 3)
        XCTAssertFalse(cache.contains("one"))
        XCTAssertTrue(cache.contains("two"))
        XCTAssertTrue(cache.contains("three"))
        XCTAssertTrue(cache.contains("four"))
    }
}

final class StoredDataResetTests: XCTestCase {
    func testOnlyTixisBirdviewKeychainServicesAreOwned() {
        XCTAssertTrue(FrigateMonitor.isOwnedKeychainService("org.tixisbirdview.app.frigate"))
        XCTAssertTrue(FrigateMonitor.isOwnedKeychainService("org.tixisbirdview.app.frigate.https://example.test"))
        XCTAssertTrue(FrigateMonitor.isOwnedKeychainService("org.tixisbirdview.app.mqtt.broker.example.test"))
        XCTAssertFalse(FrigateMonitor.isOwnedKeychainService("org.tixisbirdview.app.frigate-lookalike"))
        XCTAssertFalse(FrigateMonitor.isOwnedKeychainService("org.example.password"))
    }
}

final class LiveStreamMappingRefreshTests: XCTestCase {
    func testMissingCameraMappingRetriesAfterThirtySeconds() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(FrigateMonitor.shouldRefreshLiveStreamMapping(
            for: "new_camera",
            streamNames: ["known_camera": "known_stream"],
            loadedAt: now.addingTimeInterval(-10),
            lastAttemptAt: now.addingTimeInterval(-29),
            now: now
        ))
        XCTAssertTrue(FrigateMonitor.shouldRefreshLiveStreamMapping(
            for: "new_camera",
            streamNames: ["known_camera": "known_stream"],
            loadedAt: now.addingTimeInterval(-10),
            lastAttemptAt: now.addingTimeInterval(-30),
            now: now
        ))
    }

    func testKnownMappingRefreshesAfterFiveMinutes() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(FrigateMonitor.shouldRefreshLiveStreamMapping(
            for: "camera",
            streamNames: ["camera": "stream"],
            loadedAt: now.addingTimeInterval(-300),
            lastAttemptAt: now.addingTimeInterval(-300),
            now: now
        ))
        XCTAssertFalse(FrigateMonitor.shouldRefreshLiveStreamMapping(
            for: "camera",
            streamNames: ["camera": "stream"],
            loadedAt: now.addingTimeInterval(-330),
            lastAttemptAt: now.addingTimeInterval(-10),
            now: now
        ))
    }
}
