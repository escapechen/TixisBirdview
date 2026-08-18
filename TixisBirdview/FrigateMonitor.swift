//
//  FrigateMonitor.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 22.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import AppKit
import Foundation
import Observation
import Security
import SwiftUI

enum SecureRedirectPolicy {
    static func allowsRedirect(from sourceURL: URL, to destinationURL: URL) -> Bool {
        guard let sourceOrigin = originComponents(for: sourceURL),
              let destinationOrigin = originComponents(for: destinationURL) else {
            return false
        }

        return sourceOrigin == destinationOrigin
    }

    private static func originComponents(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }
}

final class SecureURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let sourceURL = response.url,
              let destinationURL = request.url,
              SecureRedirectPolicy.allowsRedirect(from: sourceURL, to: destinationURL) else {
            completionHandler(nil)
            return
        }

        completionHandler(request)
    }
}

struct FrigateLoginRequest {
    static func make(baseURL: URL, username: String, password: String) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "api/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["user": username, "password": password]
        )
        return request
    }

    static func sessionCookies(from response: HTTPURLResponse, for loginURL: URL) -> [HTTPCookie] {
        let responseHeaders = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            guard let name = entry.key as? String, let value = entry.value as? String else {
                return
            }
            result[name] = value
        }
        return HTTPCookie.cookies(withResponseHeaderFields: responseHeaders, for: loginURL)
    }
}

@MainActor
@Observable
final class FrigateMonitor {
    enum FeedMode: String, CaseIterable, Identifiable {
        case jpeg
        case stream

        var id: String { rawValue }

        var title: String {
            switch self {
            case .jpeg:
                "JPEG snapshots"
            case .stream:
                "Live stream"
            }
        }

        var detail: String {
            switch self {
            case .jpeg:
                "One image every 0.5 seconds"
            case .stream:
                "Low-latency go2rtc MSE video"
            }
        }
    }

    enum LiveStreamRoutingStatus: Equatable {
        case resolving
        case ready
        case unavailable
    }

    enum EventDeliveryMode: String, CaseIterable, Identifiable {
        case httpPolling
        case mqtt

        var id: String { rawValue }

        var title: String {
            switch self {
            case .httpPolling:
                "HTTP polling — compatible default"
            case .mqtt:
                "MQTT — lower-latency event delivery"
            }
        }

        var detail: String {
            switch self {
            case .httpPolling:
                "Checks Frigate for events every two seconds without requiring a broker."
            case .mqtt:
                "Receives Frigate events as they arrive from an MQTT broker. It does not change camera or detection latency."
            }
        }
    }

    enum PopupTrigger: String, CaseIterable, Identifiable {
        case selectedClassifications
        case anyObject

        var id: String { rawValue }

        var title: String {
            switch self {
            case .selectedClassifications:
                "Selected classifications"
            case .anyObject:
                "Any tracked object"
            }
        }

        var detail: String {
            switch self {
            case .selectedClassifications:
                "Only the classifications checked below trigger a popup."
            case .anyObject:
                "Every Frigate object event triggers a popup."
            }
        }
    }

    enum AlertSound: String, CaseIterable, Identifiable {
        case basso = "Basso"
        case blow = "Blow"
        case bottle = "Bottle"
        case frog = "Frog"
        case funk = "Funk"
        case glass = "Glass"
        case hero = "Hero"
        case morse = "Morse"
        case ping = "Ping"
        case pop = "Pop"
        case purr = "Purr"
        case sosumi = "Sosumi"
        case submarine = "Submarine"
        case tink = "Tink"

        var id: String { rawValue }

        var title: String { rawValue }
    }

    enum ConnectionState {
        case idle
        case connecting
        case connected
        case failed(String)

        var title: String {
            switch self {
            case .idle:
                "Idle"
            case .connecting:
                "Connecting"
            case .connected:
                "Connected"
            case .failed(let message):
                message
            }
        }

        var systemImage: String {
            switch self {
            case .idle:
                "circle"
            case .connecting:
                "arrow.triangle.2.circlepath"
            case .connected:
                "checkmark.circle.fill"
            case .failed:
                "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .idle:
                .secondary
            case .connecting:
                .blue
            case .connected:
                .green
            case .failed:
                .red
            }
        }

        var isFailure: Bool {
            if case .failed = self {
                return true
            }

            return false
        }
    }

    enum ServerAddressValidationError: LocalizedError {
        case empty
        case invalidURL
        case unsupportedScheme
        case missingHost
        case invalidPort
        case insecureTransportRequiresConfirmation

        var errorDescription: String? {
            switch self {
            case .empty:
                "Enter a server address."
            case .invalidURL:
                "Enter a valid address, for example https://frigate.example.net:8971."
            case .unsupportedScheme:
                "Use http:// or https://."
            case .missingHost:
                "Enter a host or IP address."
            case .invalidPort:
                "Use a numeric port from 1 to 65535."
            case .insecureTransportRequiresConfirmation:
                "HTTP is not encrypted. Review the warning and explicitly confirm this connection."
            }
        }
    }

    enum AuthenticationError: LocalizedError {
        case passwordWithoutUsername
        case missingPassword
        case loginFailed
        case missingSessionCookie
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .passwordWithoutUsername:
                "Enter a username with the password."
            case .missingPassword:
                "Enter the Frigate password."
            case .loginFailed:
                "Frigate rejected the username or password."
            case .missingSessionCookie:
                "Frigate did not return an authenticated session."
            case .keychain(let status):
                "Could not access the macOS Keychain (\(status))."
            }
        }
    }

    enum RequestError: LocalizedError {
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .httpStatus(let statusCode):
                "Frigate returned HTTP \(statusCode)."
            }
        }
    }

    enum DataResetError: LocalizedError {
        case keychain(OSStatus)
        case missingBundleIdentifier

        var errorDescription: String? {
            switch self {
            case .keychain(let status):
                "Could not delete credentials from the macOS Keychain (\(status))."
            case .missingBundleIdentifier:
                "Could not identify the app preferences to delete."
            }
        }
    }

    enum MqttConfigurationError: LocalizedError {
        case missingHost
        case invalidHost
        case invalidPort
        case missingTopicPrefix
        case passwordWithoutUsername
        case missingPassword
        case insecureTransportRequiresConfirmation
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .missingHost:
                "Enter an MQTT broker host."
            case .invalidHost:
                "Enter only an MQTT host or IP address, without a scheme, port, path, or credentials."
            case .invalidPort:
                "Use an MQTT port from 1 to 65535."
            case .missingTopicPrefix:
                "Enter a concrete MQTT topic prefix, such as frigate."
            case .passwordWithoutUsername:
                "Enter an MQTT username with the password."
            case .missingPassword:
                "Enter the MQTT password."
            case .insecureTransportRequiresConfirmation:
                "MQTT without TLS is not encrypted. Review the warning and explicitly confirm this connection."
            case .keychain(let status):
                "Could not access the macOS Keychain (\(status))."
            }
        }
    }

    struct OverlayActivity: Equatable {
        let title: String
        let confidence: String?
        let camera: String
        let date: Date

        var detail: String {
            "\(camera) • \(date.formatted(date: .omitted, time: .shortened))"
        }
    }

    var serverAddress: String {
        didSet {
            UserDefaults.standard.set(serverAddress, forKey: Self.serverAddressKey)
        }
    }

    var username: String {
        didSet {
            UserDefaults.standard.set(username, forKey: Self.usernameKey)
        }
    }

    var overlayDurationSeconds: Double {
        didSet {
            UserDefaults.standard.set(overlayDurationSeconds, forKey: Self.overlayDurationKey)
            if shouldShowOverlay {
                scheduleOverlayDismissal()
            }
        }
    }

    var feedMode: FeedMode {
        didSet {
            UserDefaults.standard.set(feedMode.rawValue, forKey: Self.feedModeKey)
        }
    }

    var liveStartupTimeoutSeconds: Int {
        didSet {
            let validValue = min(15, max(1, liveStartupTimeoutSeconds))
            guard validValue == liveStartupTimeoutSeconds else {
                liveStartupTimeoutSeconds = validValue
                return
            }
            UserDefaults.standard.set(liveStartupTimeoutSeconds, forKey: Self.liveStartupTimeoutKey)
        }
    }

    var isLiveDebugEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isLiveDebugEnabled, forKey: Self.liveDebugEnabledKey)
        }
    }

    var eventDeliveryMode: EventDeliveryMode {
        didSet {
            UserDefaults.standard.set(eventDeliveryMode.rawValue, forKey: Self.eventDeliveryModeKey)
            guard isMonitoring else { return }
            if eventDeliveryMode == .mqtt {
                pollingTask?.cancel()
                pollingTask = nil
                startMqttDelivery()
                startInitialHttpSync()
            } else {
                mqttClient.stop()
                startPolling()
            }
        }
    }

    var mqttBrokerHost: String {
        didSet { UserDefaults.standard.set(mqttBrokerHost, forKey: Self.mqttBrokerHostKey) }
    }

    var mqttBrokerPort: Int {
        didSet { UserDefaults.standard.set(mqttBrokerPort, forKey: Self.mqttBrokerPortKey) }
    }

    var mqttUsesTLS: Bool {
        didSet { UserDefaults.standard.set(mqttUsesTLS, forKey: Self.mqttUsesTLSKey) }
    }

    var mqttUsername: String {
        didSet { UserDefaults.standard.set(mqttUsername, forKey: Self.mqttUsernameKey) }
    }

    var mqttTopicPrefix: String {
        didSet { UserDefaults.standard.set(mqttTopicPrefix, forKey: Self.mqttTopicPrefixKey) }
    }

    var popupTrigger: PopupTrigger {
        didSet {
            UserDefaults.standard.set(popupTrigger.rawValue, forKey: Self.popupTriggerKey)
        }
    }

    var isSoundAlertEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSoundAlertEnabled, forKey: Self.soundAlertEnabledKey)
        }
    }

    var alertSound: AlertSound {
        didSet {
            UserDefaults.standard.set(alertSound.rawValue, forKey: Self.alertSoundKey)
        }
    }

    var soundAlertVolume: Double {
        didSet {
            UserDefaults.standard.set(soundAlertVolume, forKey: Self.soundAlertVolumeKey)
        }
    }

    var isPopupCooldownEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isPopupCooldownEnabled, forKey: Self.popupCooldownEnabledKey)
            if !isPopupCooldownEnabled {
                lastAutomaticPopupDate = nil
            }
        }
    }

    var popupCooldownSeconds: Int {
        didSet {
            let validValue = max(1, popupCooldownSeconds)
            guard validValue == popupCooldownSeconds else {
                popupCooldownSeconds = validValue
                return
            }
            UserDefaults.standard.set(popupCooldownSeconds, forKey: Self.popupCooldownKey)
        }
    }

    var isSoundCooldownEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSoundCooldownEnabled, forKey: Self.soundCooldownEnabledKey)
            if !isSoundCooldownEnabled {
                lastAutomaticSoundDate = nil
            }
        }
    }

    var soundCooldownSeconds: Int {
        didSet {
            let validValue = max(1, soundCooldownSeconds)
            guard validValue == soundCooldownSeconds else {
                soundCooldownSeconds = validValue
                return
            }
            UserDefaults.standard.set(soundCooldownSeconds, forKey: Self.soundCooldownKey)
        }
    }

    var selectedClassificationNames: Set<String> {
        didSet {
            UserDefaults.standard.set(selectedClassificationNames.sorted(), forKey: Self.selectedClassificationsKey)
        }
    }

    let defaultFeedCameraName = "birdseye"

    var isMonitoring = false
    var shouldShowOverlay = false {
        didSet {
            if shouldShowOverlay {
                overlayPresentationID = UUID()
            }
            onOverlayVisibilityChanged?(shouldShowOverlay)

            if shouldShowOverlay {
                scheduleOverlayDismissal()
            } else {
                overlayDismissalTask?.cancel()
                overlayDismissalTask = nil
                overlayDismissalDate = nil
            }
        }
    }
    var connectionState: ConnectionState = .idle {
        didSet {
            onConnectionStateChanged?(connectionState)
        }
    }
    var lastEventDescription = "No event detected"
    var serverAddressError: String?
    var latestEvent: FrigateEvent?
    var latestReviewItem: FrigateReviewItem?
    var overlayDismissalDate: Date?
    var overlayActivity: OverlayActivity?
    var overlayPresentationID = UUID()
    var streamSessionID = UUID()
    var liveStreamNames: [String: String] = [:]
    var liveStreamRoutingError: String?
    var availableClassificationNames: [String] = []
    var isLoadingClassifications = false
    var classificationLoadError: String?
    var eventDeliveryStatus = "HTTP polling is ready."
    var isMqttVerificationInProgress = false
    var mqttVerificationStatus: String?

    @ObservationIgnored var onOverlayVisibilityChanged: ((Bool) -> Void)?
    @ObservationIgnored var onConnectionStateChanged: ((ConnectionState) -> Void)?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private lazy var mqttClient = MqttClient(
        onStateChange: { [weak self] isConnected, detail in
            guard let self, self.isMonitoring, self.eventDeliveryMode == .mqtt else { return }
            self.connectionState = isConnected ? .connected : .failed(detail)
            self.eventDeliveryStatus = detail
        },
        onMessage: { [weak self] topic, payload in
            self?.receiveMqttMessage(topic: topic, payload: payload)
        }
    )
    @ObservationIgnored private lazy var mqttVerifier = MqttClient(
        onStateChange: { [weak self] isConnected, detail in
            guard let self, self.isMqttVerificationInProgress else { return }
            self.completeMqttVerification(
                isConnected
                    ? "MQTT verification succeeded: the broker accepted the connection and both Frigate topic subscriptions."
                    : "MQTT verification failed: \(detail)"
            )
        },
        onMessage: { _, _ in }
    )
    @ObservationIgnored private var overlayDismissalTask: Task<Void, Never>?
    @ObservationIgnored private var seenEventIDs = RecentIdentifierCache(capacity: 512)
    @ObservationIgnored private var seenReviewItemIDs = RecentIdentifierCache(capacity: 512)
    @ObservationIgnored private var urlSession: URLSession
    @ObservationIgnored private let passwordProvider: (String, String) throws -> String?
    @ObservationIgnored private var hasAuthenticatedSession = false
    @ObservationIgnored private var isLoadingLiveStreamNames = false
    private var hasLoadedLiveStreamNames = false
    @ObservationIgnored private var liveStreamNamesLoadedAt: Date?
    @ObservationIgnored private var liveStreamNamesRefreshAttemptedAt: Date?
    @ObservationIgnored private var alertSoundPlayer: NSSound?
    @ObservationIgnored private var lastAlertSoundDate: Date?
    @ObservationIgnored private var lastAutomaticPopupDate: Date?
    @ObservationIgnored private var lastAutomaticSoundDate: Date?

    private static let serverAddressKey = "serverAddress"
    private static let usernameKey = "serverUsername"
    private static let overlayDurationKey = "overlayDurationSeconds"
    private static let feedModeKey = "feedMode"
    private static let liveStartupTimeoutKey = "liveStartupTimeoutSeconds"
    private static let liveDebugEnabledKey = "liveDebugEnabled"
    private static let eventDeliveryModeKey = "eventDeliveryMode"
    private static let mqttBrokerHostKey = "mqttBrokerHost"
    private static let mqttBrokerPortKey = "mqttBrokerPort"
    private static let mqttUsesTLSKey = "mqttUsesTLS"
    private static let mqttUsernameKey = "mqttUsername"
    private static let mqttTopicPrefixKey = "mqttTopicPrefix"
    private static let popupTriggerKey = "popupTrigger"
    private static let soundAlertEnabledKey = "soundAlertEnabled"
    private static let alertSoundKey = "alertSound"
    private static let soundAlertVolumeKey = "soundAlertVolume"
    private static let popupCooldownEnabledKey = "popupCooldownEnabled"
    private static let popupCooldownKey = "popupCooldownSeconds"
    private static let soundCooldownEnabledKey = "soundCooldownEnabled"
    private static let soundCooldownKey = "soundCooldownSeconds"
    private static let selectedClassificationsKey = "selectedClassificationNames"
    private static let confirmedInsecureServerAddressKey = "confirmedInsecureServerAddress"
    private static let confirmedInsecureMqttEndpointKey = "confirmedInsecureMqttEndpoint"
    private static let defaultServerAddress = "https://frigate.invalid"
    private static let defaultOverlayDurationSeconds = 20.0
    private static let defaultLiveStartupTimeoutSeconds = 5
    private static let defaultSoundAlertVolume = 0.6
    private static let defaultCooldownSeconds = 60
    private static let liveStreamMappingRefreshInterval: TimeInterval = 5 * 60
    private static let missingLiveStreamMappingRetryInterval: TimeInterval = 30
    private static let defaultSelectedClassificationNames: Set<String> = ["bird", "cat", "bruno"]
    private static let keychainService = "org.tixisbirdview.app.frigate"
    private static let mqttKeychainService = "org.tixisbirdview.app.mqtt"

    init(
        urlSession: URLSession? = nil,
        passwordProvider: ((String, String) throws -> String?)? = nil
    ) {
        let usesSystemKeychain = passwordProvider == nil
        self.urlSession = urlSession ?? Self.makeURLSession()
        self.passwordProvider = passwordProvider ?? Self.savedPassword
        let savedOverlayDuration = UserDefaults.standard.double(forKey: Self.overlayDurationKey)
        overlayDurationSeconds = savedOverlayDuration > 0 ? savedOverlayDuration : Self.defaultOverlayDurationSeconds
        feedMode = FeedMode(rawValue: UserDefaults.standard.string(forKey: Self.feedModeKey) ?? "") ?? .jpeg
        liveStartupTimeoutSeconds = UserDefaults.standard.object(forKey: Self.liveStartupTimeoutKey) == nil
            ? Self.defaultLiveStartupTimeoutSeconds
            : min(15, max(1, UserDefaults.standard.integer(forKey: Self.liveStartupTimeoutKey)))
        isLiveDebugEnabled = UserDefaults.standard.bool(forKey: Self.liveDebugEnabledKey)
        eventDeliveryMode = EventDeliveryMode(
            rawValue: UserDefaults.standard.string(forKey: Self.eventDeliveryModeKey) ?? ""
        ) ?? .httpPolling
        mqttBrokerHost = UserDefaults.standard.string(forKey: Self.mqttBrokerHostKey) ?? ""
        mqttBrokerPort = min(65535, max(
            1,
            UserDefaults.standard.object(forKey: Self.mqttBrokerPortKey) == nil
                ? 8883
                : UserDefaults.standard.integer(forKey: Self.mqttBrokerPortKey)
        ))
        mqttUsesTLS = UserDefaults.standard.object(forKey: Self.mqttUsesTLSKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Self.mqttUsesTLSKey)
        mqttUsername = UserDefaults.standard.string(forKey: Self.mqttUsernameKey) ?? ""
        let savedMqttTopicPrefix = UserDefaults.standard.string(forKey: Self.mqttTopicPrefixKey) ?? "frigate"
        mqttTopicPrefix = savedMqttTopicPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "frigate"
            : savedMqttTopicPrefix
        popupTrigger = PopupTrigger(rawValue: UserDefaults.standard.string(forKey: Self.popupTriggerKey) ?? "") ?? .selectedClassifications
        isSoundAlertEnabled = UserDefaults.standard.bool(forKey: Self.soundAlertEnabledKey)
        alertSound = AlertSound(rawValue: UserDefaults.standard.string(forKey: Self.alertSoundKey) ?? "") ?? .purr
        soundAlertVolume = UserDefaults.standard.object(forKey: Self.soundAlertVolumeKey) == nil
            ? Self.defaultSoundAlertVolume
            : UserDefaults.standard.double(forKey: Self.soundAlertVolumeKey)
        isPopupCooldownEnabled = UserDefaults.standard.bool(forKey: Self.popupCooldownEnabledKey)
        popupCooldownSeconds = UserDefaults.standard.object(forKey: Self.popupCooldownKey) == nil
            ? Self.defaultCooldownSeconds
            : max(1, UserDefaults.standard.integer(forKey: Self.popupCooldownKey))
        isSoundCooldownEnabled = UserDefaults.standard.bool(forKey: Self.soundCooldownEnabledKey)
        soundCooldownSeconds = UserDefaults.standard.object(forKey: Self.soundCooldownKey) == nil
            ? Self.defaultCooldownSeconds
            : max(1, UserDefaults.standard.integer(forKey: Self.soundCooldownKey))
        selectedClassificationNames = Set(
            (UserDefaults.standard.stringArray(forKey: Self.selectedClassificationsKey)
                ?? Array(Self.defaultSelectedClassificationNames))
            .map(\.normalizedDetectionName)
        )

        let savedServerAddress = UserDefaults.standard.string(forKey: Self.serverAddressKey) ?? Self.defaultServerAddress
        username = UserDefaults.standard.string(forKey: Self.usernameKey) ?? ""
        do {
            serverAddress = try Self.validatedServerAddress(savedServerAddress)
        } catch {
            serverAddress = Self.defaultServerAddress
            UserDefaults.standard.set(serverAddress, forKey: Self.serverAddressKey)
            serverAddressError = "Saved server address was invalid and has been reset."
        }
        if usesSystemKeychain, !username.isEmpty {
            try? Self.migrateLegacyPasswordIfNeeded(
                serverAddress: serverAddress,
                username: username
            )
        }
        if !isFrigateTransportApproved {
            serverAddressError = ServerAddressValidationError
                .insecureTransportRequiresConfirmation
                .localizedDescription
        }
        availableClassificationNames = selectedClassificationNames.sorted()
    }

    var baseURL: URL? {
        guard isFrigateTransportApproved else {
            return nil
        }
        return URL(string: serverAddress)
    }

    private var isFrigateTransportApproved: Bool {
        !Self.requiresInsecureTransportConfirmation(serverAddress)
            || UserDefaults.standard.string(forKey: Self.confirmedInsecureServerAddressKey) == serverAddress
    }

    var currentFeedCameraName: String {
        switch (latestEvent, latestReviewItem) {
        case let (event?, review?):
            let eventActivityTime = event.endTime ?? event.startTime
            return eventActivityTime >= review.activityTime ? event.camera : review.camera
        case let (event?, nil):
            return event.camera
        case let (nil, review?):
            return review.camera
        case (nil, nil):
            return defaultFeedCameraName
        }
    }

    var currentFeedStreamName: String {
        liveStreamNames[currentFeedCameraName] ?? currentFeedCameraName
    }

    var liveStreamRoutingStatus: LiveStreamRoutingStatus {
        if liveStreamRoutingError != nil {
            return .unavailable
        }
        guard hasLoadedLiveStreamNames else {
            return .resolving
        }
        return liveStreamNames[currentFeedCameraName] == nil ? .unavailable : .ready
    }

    var feedURL: URL {
        guard let baseURL else {
            return URL(string: Self.defaultServerAddress)!.appending(path: "api/\(currentFeedCameraName)/latest.jpg")
        }

        return baseURL.appending(path: "api/\(currentFeedCameraName)/latest.jpg")
    }

    func authenticationCookies() -> [HTTPCookie] {
        guard let baseURL else {
            return []
        }

        return urlSession.configuration.httpCookieStorage?.cookies(for: baseURL) ?? []
    }

    func isClassificationSelected(_ name: String) -> Bool {
        selectedClassificationNames.contains(name.normalizedDetectionName)
    }

    func setClassification(_ name: String, isSelected: Bool) {
        let normalizedName = name.normalizedDetectionName
        guard !normalizedName.isEmpty else {
            return
        }

        if isSelected {
            selectedClassificationNames.insert(normalizedName)
            if !availableClassificationNames.contains(where: {
                $0.normalizedDetectionName == normalizedName
            }) {
                availableClassificationNames.append(name.trimmingCharacters(in: .whitespacesAndNewlines))
                availableClassificationNames.sort {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }
            }
        } else {
            selectedClassificationNames.remove(normalizedName)
        }
    }

    func refreshAvailableClassifications() {
        guard !isLoadingClassifications else {
            return
        }

        isLoadingClassifications = true
        classificationLoadError = nil

        Task { [weak self] in
            guard let self else {
                return
            }

            defer { isLoadingClassifications = false }

            do {
                try await authenticateIfNeeded()
                let classifications = try await fetchAvailableClassifications()
                availableClassificationNames = Array(
                    Set(classifications + selectedClassificationNames)
                ).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            } catch {
                classificationLoadError = Self.statusMessage(for: error)
            }
        }
    }

    func start() {
        guard !isMonitoring else {
            return
        }

        isMonitoring = true
        connectionState = .connecting
        if eventDeliveryMode == .mqtt {
            startMqttDelivery()
            startInitialHttpSync()
        } else {
            startPolling()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        mqttClient.stop()
        isMonitoring = false
        connectionState = .idle
        eventDeliveryStatus = "Event delivery is stopped."
    }

    func deleteAllStoredData() throws {
        stop()
        mqttVerifier.stop()
        shouldShowOverlay = false
        try Self.deleteAllStoredCredentials()

        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            throw DataResetError.missingBundleIdentifier
        }
        UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
    }

    func toggleMonitoring() {
        if isMonitoring {
            stop()
        } else {
            start()
        }
    }

    func showOverlayForLatestEvent() {
        shouldShowOverlay = true
    }

    func dismissOverlay() {
        shouldShowOverlay = false
    }

    func previewSoundAlert() {
        playSoundAlert(force: true)
    }

    @discardableResult
    func applyMqttSettings(
        host: String,
        port: Int,
        useTLS: Bool,
        username newUsername: String,
        password: String,
        topicPrefix: String,
        allowInsecureTransport: Bool = false
    ) -> Bool {
        do {
            let normalizedHost = try Self.validatedMqttHost(host)
            let normalizedTopicPrefix = try Self.validatedMqttTopicPrefix(topicPrefix)
            guard (1...65535).contains(port) else {
                throw MqttConfigurationError.invalidPort
            }
            guard useTLS || allowInsecureTransport else {
                throw MqttConfigurationError.insecureTransportRequiresConfirmation
            }
            try updateMqttCredentials(host: normalizedHost, username: newUsername, password: password)
            mqttBrokerHost = normalizedHost
            mqttBrokerPort = port
            mqttUsesTLS = useTLS
            mqttTopicPrefix = normalizedTopicPrefix
            if useTLS {
                UserDefaults.standard.removeObject(forKey: Self.confirmedInsecureMqttEndpointKey)
            } else {
                UserDefaults.standard.set(
                    Self.mqttEndpointScope(host: normalizedHost, port: port),
                    forKey: Self.confirmedInsecureMqttEndpointKey
                )
            }
            mqttVerificationStatus = nil
        } catch {
            mqttVerificationStatus = "MQTT settings were not applied: \(error.localizedDescription)"
            return false
        }

        if isMonitoring, eventDeliveryMode == .mqtt {
            mqttClient.stop()
            startMqttDelivery()
        }
        return true
    }

    func verifyMqttConnection() {
        guard !isMqttVerificationInProgress else { return }
        do {
            let configuration = try mqttConfiguration()
            isMqttVerificationInProgress = true
            mqttVerificationStatus = "Verifying the MQTT connection and Frigate topic subscriptions…"
            mqttVerifier.start(configuration)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard let self, self.isMqttVerificationInProgress else { return }
                self.completeMqttVerification(
                    "MQTT verification timed out before the broker confirmed both subscriptions."
                )
            }
        } catch {
            mqttVerificationStatus = "MQTT verification failed: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func applyServerAddress(_ address: String) -> Bool {
        applyConnectionSettings(address, username: username, password: "")
    }

    @discardableResult
    func applyConnectionSettings(
        _ address: String,
        username newUsername: String,
        password: String,
        allowInsecureTransport: Bool = false
    ) -> Bool {
        do {
            let validatedAddress = try Self.validatedServerAddress(address)
            guard !Self.requiresInsecureTransportConfirmation(validatedAddress)
                    || allowInsecureTransport else {
                throw ServerAddressValidationError.insecureTransportRequiresConfirmation
            }
            try updateCredentials(
                serverAddress: validatedAddress,
                username: newUsername,
                password: password
            )
            serverAddress = validatedAddress
            if Self.requiresInsecureTransportConfirmation(validatedAddress) {
                UserDefaults.standard.set(
                    validatedAddress,
                    forKey: Self.confirmedInsecureServerAddressKey
                )
            } else {
                UserDefaults.standard.removeObject(forKey: Self.confirmedInsecureServerAddressKey)
            }
            serverAddressError = nil
        } catch {
            serverAddressError = error.localizedDescription
            connectionState = .failed(error.localizedDescription)
            return false
        }

        let wasMonitoring = isMonitoring
        if wasMonitoring {
            stop()
        }

        resetAuthenticatedSession()

        if wasMonitoring {
            start()
        }

        return true
    }

    private func startPolling() {
        mqttClient.stop()
        eventDeliveryStatus = "HTTP polling every 2 seconds."
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollActivity()

                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    break
                }
            }
        }
    }

    private func startInitialHttpSync() {
        Task { [weak self] in
            await self?.pollActivity()
        }
    }

    private func startMqttDelivery() {
        do {
            let configuration = try mqttConfiguration()
            eventDeliveryStatus = "Connecting to MQTT…"
            mqttClient.start(configuration)
        } catch {
            let detail = error.localizedDescription
            eventDeliveryStatus = detail
            connectionState = .failed(detail)
        }
    }

    private func mqttConfiguration() throws -> MqttClient.Configuration {
        let host = try Self.validatedMqttHost(mqttBrokerHost)
        let topicPrefix = try Self.validatedMqttTopicPrefix(mqttTopicPrefix)
        guard (1...65535).contains(mqttBrokerPort) else {
            throw MqttConfigurationError.invalidPort
        }
        guard mqttUsesTLS
                || UserDefaults.standard.string(forKey: Self.confirmedInsecureMqttEndpointKey)
                    == Self.mqttEndpointScope(host: host, port: mqttBrokerPort) else {
            throw MqttConfigurationError.insecureTransportRequiresConfirmation
        }
        let normalizedUsername = mqttUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let password: String
        if normalizedUsername.isEmpty {
            password = ""
        } else if let savedPassword = try Self.savedMqttPassword(host: host, username: normalizedUsername) {
            password = savedPassword
        } else {
            throw MqttConfigurationError.missingPassword
        }
        return MqttClient.Configuration(
            host: host,
            port: UInt16(mqttBrokerPort),
            useTLS: mqttUsesTLS,
            username: normalizedUsername,
            password: password,
            topicPrefix: topicPrefix
        )
    }

    private func completeMqttVerification(_ status: String) {
        guard isMqttVerificationInProgress else { return }
        isMqttVerificationInProgress = false
        mqttVerifier.stop()
        mqttVerificationStatus = status
    }

    func receiveMqttMessage(topic: String, payload: Data) {
        guard isMonitoring, eventDeliveryMode == .mqtt,
              let topicPrefix = try? Self.validatedMqttTopicPrefix(mqttTopicPrefix) else {
            return
        }

        let decoder = JSONDecoder()
        switch topic {
        case "\(topicPrefix)/events":
            guard let event = try? decoder.decode(MqttEnvelope<FrigateEvent>.self, from: payload).after else {
                return
            }
            handle(events: [event])
        case "\(topicPrefix)/reviews":
            guard let review = try? decoder.decode(MqttEnvelope<FrigateReviewItem>.self, from: payload).after else {
                return
            }
            handle(reviewItems: [review])
        default:
            return
        }
    }

    private func pollActivity() async {
        guard !Task.isCancelled else {
            return
        }

        do {
            try await authenticateIfNeeded()
        } catch {
            guard !Task.isCancelled else {
                return
            }
            connectionState = .failed(Self.statusMessage(for: error))
            return
        }

        await ensureLiveStreamNamesLoaded(
            forceRefresh: Self.shouldRefreshLiveStreamMapping(
                for: currentFeedCameraName,
                streamNames: liveStreamNames,
                loadedAt: liveStreamNamesLoadedAt,
                lastAttemptAt: liveStreamNamesRefreshAttemptedAt
            )
        )

        async let reviewItemsResult = fetchRecentReviewItems()
        async let eventsResult = fetchRecentEvents()

        var pollingError: Error?

        do {
            let reviewItems = try await reviewItemsResult
            handle(reviewItems: reviewItems)
        } catch {
            pollingError = error
        }

        do {
            let events = try await eventsResult
            handle(events: events)
        } catch {
            if pollingError == nil {
                pollingError = error
            }
        }

        guard !Task.isCancelled else {
            return
        }

        guard eventDeliveryMode == .httpPolling else {
            return
        }

        if let pollingError {
            connectionState = .failed(Self.statusMessage(for: pollingError))
        } else {
            connectionState = .connected
        }
    }

    private func fetchRecentEvents() async throws -> [FrigateEvent] {
        guard let baseURL else {
            throw ServerAddressValidationError.invalidURL
        }

        var components = URLComponents(url: baseURL.appending(path: "api/events"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "25")
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let data = try await requestData(for: URLRequest(url: url))
        return try JSONDecoder().decode([FrigateEvent].self, from: data)
    }

    private func fetchRecentReviewItems() async throws -> [FrigateReviewItem] {
        guard let baseURL else {
            throw ServerAddressValidationError.invalidURL
        }

        var components = URLComponents(url: baseURL.appending(path: "api/review"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "10")
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let data = try await requestData(for: URLRequest(url: url))
        return try JSONDecoder().decode([FrigateReviewItem].self, from: data)
    }

    func fetchLatestFrame() async throws -> Data {
        // MQTT can continue to deliver events after Frigate expires an HTTP
        // session. Refresh it here so the JPEG fallback remains usable.
        try await authenticateIfNeeded()

        var components = URLComponents(url: feedURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "t", value: "\(Date().timeIntervalSince1970)")
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 5
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return try await requestData(for: request)
    }

    private func handle(reviewItems: [FrigateReviewItem]) {
        guard let newestItem = (
            reviewItems
            .filter { isRelevant(reviewItem: $0) }
            .max(by: { $0.activityTime < $1.activityTime })
        ) else {
            return
        }

        latestReviewItem = newestItem
        scheduleLiveStreamMappingRefreshIfNeeded(for: newestItem.camera)

        let isNewItem = seenReviewItemIDs.insert(newestItem.id)
        let isRecent = Date().timeIntervalSince(newestItem.activityDate) < 120
        if isNewItem && isRecent {
            lastEventDescription = newestItem.displayDescription
            presentAutomaticAlert(
                OverlayActivity(
                    title: newestItem.data.bestObjectDescription,
                    confidence: nil,
                    camera: newestItem.camera,
                    date: newestItem.activityDate
                )
            )
        }
    }

    private func handle(events: [FrigateEvent]) {
        guard let newestEvent = (
            events
            .filter { isRelevant(event: $0) }
            .max(by: { $0.startTime < $1.startTime })
        ) else {
            if latestReviewItem == nil {
                lastEventDescription = "No recent monitored activity"
            }
            return
        }

        latestEvent = newestEvent
        lastEventDescription = newestEvent.displayDescription
        scheduleLiveStreamMappingRefreshIfNeeded(for: newestEvent.camera)

        let isNewEvent = seenEventIDs.insert(newestEvent.id)
        let isRecent = Date().timeIntervalSince(newestEvent.startedAt) < 90
        if isNewEvent && isRecent {
            presentAutomaticAlert(
                OverlayActivity(
                    title: newestEvent.displayLabel,
                    confidence: newestEvent.confidenceDescription,
                    camera: newestEvent.camera,
                    date: newestEvent.startedAt
                )
            )
        }
    }

    private func presentAutomaticAlert(_ activity: OverlayActivity) {
        if shouldShowAutomaticPopup() {
            overlayActivity = activity
            shouldShowOverlay = true
        }

        playSoundAlertIfEnabled()
    }

    private func shouldShowAutomaticPopup() -> Bool {
        guard isPopupCooldownEnabled else {
            return true
        }

        let now = Date()
        if let lastAutomaticPopupDate,
           now.timeIntervalSince(lastAutomaticPopupDate) < TimeInterval(popupCooldownSeconds) {
            return false
        }

        lastAutomaticPopupDate = now
        return true
    }

    private func playSoundAlertIfEnabled() {
        guard isSoundAlertEnabled else {
            return
        }

        let now = Date()
        if isSoundCooldownEnabled,
           let lastAutomaticSoundDate,
           now.timeIntervalSince(lastAutomaticSoundDate) < TimeInterval(soundCooldownSeconds) {
            return
        }

        guard playSoundAlert(force: false) else {
            return
        }

        if isSoundCooldownEnabled {
            lastAutomaticSoundDate = now
        }
    }

    @discardableResult
    private func playSoundAlert(force: Bool) -> Bool {
        let now = Date()
        if !force,
           let lastAlertSoundDate,
           now.timeIntervalSince(lastAlertSoundDate) < 1 {
            return false
        }

        guard let sound = NSSound(named: NSSound.Name(alertSound.rawValue)) else {
            return false
        }

        lastAlertSoundDate = now
        sound.stop()
        sound.volume = Float(soundAlertVolume)
        alertSoundPlayer = sound
        return sound.play()
    }

    private func isRelevant(event: FrigateEvent) -> Bool {
        switch popupTrigger {
        case .anyObject:
            !event.label.normalizedDetectionName.isEmpty
        case .selectedClassifications:
            isClassificationSelected(event.label) || isClassificationSelected(event.subLabel ?? "")
        }
    }

    private func isRelevant(reviewItem: FrigateReviewItem) -> Bool {
        switch popupTrigger {
        case .anyObject:
            !reviewItem.data.objectNames.isEmpty
        case .selectedClassifications:
            reviewItem.data.objectNames.contains { isClassificationSelected($0) }
        }
    }

    private func fetchAvailableClassifications() async throws -> [String] {
        guard let baseURL else {
            throw ServerAddressValidationError.invalidURL
        }

        let labelsURL = baseURL.appending(path: "api/labels")
        var subLabelsComponents = URLComponents(
            url: baseURL.appending(path: "api/sub_labels"),
            resolvingAgainstBaseURL: false
        )
        subLabelsComponents?.queryItems = [URLQueryItem(name: "split_joined", value: "1")]

        guard let subLabelsURL = subLabelsComponents?.url else {
            throw URLError(.badURL)
        }

        async let labelsData = requestData(for: URLRequest(url: labelsURL))
        async let subLabelsData = requestData(for: URLRequest(url: subLabelsURL))
        let (labelsResponse, subLabelsResponse) = try await (labelsData, subLabelsData)
        let labels = try JSONDecoder().decode([String].self, from: labelsResponse)
        let subLabels = try JSONDecoder().decode([String].self, from: subLabelsResponse)

        return Array(Set(labels + subLabels))
            .filter { !$0.normalizedDetectionName.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func ensureLiveStreamNamesLoaded(forceRefresh: Bool = false) async {
        guard !isLoadingLiveStreamNames,
              forceRefresh || !hasLoadedLiveStreamNames else {
            return
        }

        isLoadingLiveStreamNames = true
        liveStreamNamesRefreshAttemptedAt = Date()
        liveStreamRoutingError = nil
        defer { isLoadingLiveStreamNames = false }

        do {
            try await authenticateIfNeeded()
            applyLiveStreamNames(try await fetchLiveStreamNames())
        } catch {
            // Never guess that an event camera key is also a go2rtc source.
            liveStreamRoutingError = "Live stream routing could not be loaded."
        }
    }

    func applyLiveStreamNames(_ streamNames: [String: String]) {
        let activeCamera = currentFeedCameraName
        let previousStreamName = currentFeedStreamName
        liveStreamNames = streamNames
        hasLoadedLiveStreamNames = true
        liveStreamNamesLoadedAt = Date()
        liveStreamRoutingError = nil

        // A popup may have started with its camera key before this lookup
        // completed. Recreate the MSE player with the resolved go2rtc name.
        if activeCamera == currentFeedCameraName,
           currentFeedStreamName != previousStreamName {
            streamSessionID = UUID()
        }
    }

    private func scheduleLiveStreamMappingRefreshIfNeeded(for camera: String) {
        guard feedMode == .stream,
              Self.shouldRefreshLiveStreamMapping(
                  for: camera,
                  streamNames: liveStreamNames,
                  loadedAt: liveStreamNamesLoadedAt,
                  lastAttemptAt: liveStreamNamesRefreshAttemptedAt
              ) else {
            return
        }

        Task { [weak self] in
            await self?.ensureLiveStreamNamesLoaded(forceRefresh: true)
        }
    }

    static func shouldRefreshLiveStreamMapping(
        for camera: String,
        streamNames: [String: String],
        loadedAt: Date?,
        lastAttemptAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let loadedAt else {
            return lastAttemptAt.map {
                now.timeIntervalSince($0) >= missingLiveStreamMappingRetryInterval
            } ?? true
        }

        if now.timeIntervalSince(loadedAt) >= liveStreamMappingRefreshInterval {
            return lastAttemptAt.map {
                now.timeIntervalSince($0) >= missingLiveStreamMappingRetryInterval
            } ?? true
        }

        guard streamNames[camera] == nil else {
            return false
        }
        return lastAttemptAt.map {
            now.timeIntervalSince($0) >= missingLiveStreamMappingRetryInterval
        } ?? true
    }

    private func fetchLiveStreamNames() async throws -> [String: String] {
        guard let baseURL else {
            throw ServerAddressValidationError.invalidURL
        }

        let data = try await requestData(for: URLRequest(url: baseURL.appending(path: "api/config")))
        let config = try JSONDecoder().decode(FrigateConfiguration.self, from: data)

        return config.cameras.reduce(into: [String: String]()) { streamNames, entry in
            guard let streamName = entry.value.live?.streams.values.first,
                  !streamName.isEmpty else {
                return
            }

            streamNames[entry.key] = streamName
        }
    }

    private func scheduleOverlayDismissal() {
        overlayDismissalTask?.cancel()
        let duration = overlayDurationSeconds
        overlayDismissalDate = Date().addingTimeInterval(duration)

        overlayDismissalTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(duration))
                self?.dismissOverlay()
            } catch {
                return
            }
        }
    }

    private func authenticateIfNeeded() async throws {
        guard isFrigateTransportApproved else {
            throw ServerAddressValidationError.insecureTransportRequiresConfirmation
        }
        guard !username.isEmpty, !hasAuthenticatedSession else {
            return
        }

        guard let password = try passwordProvider(serverAddress, username) else {
            throw AuthenticationError.missingPassword
        }
        guard let baseURL else {
            throw ServerAddressValidationError.invalidURL
        }

        let request = try FrigateLoginRequest.make(
            baseURL: baseURL,
            username: username,
            password: password
        )
        let loginURL = request.url ?? baseURL

        let (_, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AuthenticationError.loginFailed
            }
            throw RequestError.httpStatus(httpResponse.statusCode)
        }

        let cookies = FrigateLoginRequest.sessionCookies(from: httpResponse, for: loginURL)
        guard !cookies.isEmpty else {
            throw AuthenticationError.missingSessionCookie
        }

        urlSession.configuration.httpCookieStorage?.setCookies(
            cookies,
            for: loginURL,
            mainDocumentURL: baseURL
        )
        hasAuthenticatedSession = true
        streamSessionID = UUID()
    }

    private func requestData(for request: URLRequest) async throws -> Data {
        guard isFrigateTransportApproved else {
            throw ServerAddressValidationError.insecureTransportRequiresConfirmation
        }
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                hasAuthenticatedSession = false
            }
            throw RequestError.httpStatus(httpResponse.statusCode)
        }

        return data
    }

    private func updateCredentials(
        serverAddress newServerAddress: String,
        username newUsername: String,
        password: String
    ) throws {
        let normalizedUsername = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousServerAddress = serverAddress
        let previousUsername = username

        if normalizedUsername.isEmpty {
            guard password.isEmpty else {
                throw AuthenticationError.passwordWithoutUsername
            }
            if !previousUsername.isEmpty {
                try Self.deletePassword(
                    serverAddress: previousServerAddress,
                    username: previousUsername
                )
            }
            username = ""
            return
        }

        if password.isEmpty {
            guard try passwordProvider(newServerAddress, normalizedUsername) != nil else {
                throw AuthenticationError.missingPassword
            }
        } else {
            try Self.savePassword(
                password,
                serverAddress: newServerAddress,
                username: normalizedUsername
            )
        }

        if (previousServerAddress != newServerAddress || previousUsername != normalizedUsername),
           !previousUsername.isEmpty {
            try Self.deletePassword(
                serverAddress: previousServerAddress,
                username: previousUsername
            )
        }
        username = normalizedUsername
    }

    private func updateMqttCredentials(host: String, username newUsername: String, password: String) throws {
        let normalizedUsername = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousHost = mqttBrokerHost
        let previousUsername = mqttUsername

        if normalizedUsername.isEmpty {
            guard password.isEmpty else {
                throw MqttConfigurationError.passwordWithoutUsername
            }
            if !previousHost.isEmpty, !previousUsername.isEmpty {
                try Self.deleteMqttPassword(host: previousHost, username: previousUsername)
            }
            mqttUsername = ""
            return
        }

        if password.isEmpty {
            guard try Self.savedMqttPassword(host: host, username: normalizedUsername) != nil else {
                throw MqttConfigurationError.missingPassword
            }
        } else {
            try Self.saveMqttPassword(password, host: host, username: normalizedUsername)
        }

        if (previousHost != host || previousUsername != normalizedUsername),
           !previousHost.isEmpty,
           !previousUsername.isEmpty {
            try Self.deleteMqttPassword(host: previousHost, username: previousUsername)
        }
        mqttUsername = normalizedUsername
    }

    private func resetAuthenticatedSession() {
        urlSession.invalidateAndCancel()
        urlSession = Self.makeURLSession()
        hasAuthenticatedSession = false
        hasLoadedLiveStreamNames = false
        liveStreamNamesLoadedAt = nil
        liveStreamNamesRefreshAttemptedAt = nil
        liveStreamNames = [:]
        liveStreamRoutingError = nil
        availableClassificationNames = []
        classificationLoadError = nil
        streamSessionID = UUID()
    }

    private static func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        return URLSession(
            configuration: configuration,
            delegate: SecureURLSessionDelegate(),
            delegateQueue: nil
        )
    }

    private static func savedPassword(serverAddress: String, username: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName(for: serverAddress),
            kSecAttrAccount as String: username,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw AuthenticationError.keychain(status)
        }

        return password
    }

    private static func savePassword(
        _ password: String,
        serverAddress: String,
        username: String
    ) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName(for: serverAddress),
            kSecAttrAccount as String: username,
        ]
        let data = Data(password.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)

        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AuthenticationError.keychain(addStatus)
            }
        } else if status != errSecSuccess {
            throw AuthenticationError.keychain(status)
        }
    }

    private static func deletePassword(serverAddress: String, username: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName(for: serverAddress),
            kSecAttrAccount as String: username,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthenticationError.keychain(status)
        }
    }

    static func keychainServiceName(for serverAddress: String) -> String {
        "\(keychainService).\(serverAddress.lowercased())"
    }

    private static func migrateLegacyPasswordIfNeeded(
        serverAddress: String,
        username: String
    ) throws {
        guard let legacyPassword = try savedLegacyPassword(for: username) else {
            return
        }

        if try savedPassword(serverAddress: serverAddress, username: username) == nil {
            try savePassword(
                legacyPassword,
                serverAddress: serverAddress,
                username: username
            )
        }
        try deleteLegacyPassword(for: username)
    }

    private static func savedLegacyPassword(for username: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: username,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw AuthenticationError.keychain(status)
        }
        return password
    }

    private static func deleteLegacyPassword(for username: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: username,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthenticationError.keychain(status)
        }
    }

    private static func savedMqttPassword(host: String, username: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: mqttKeychainServiceName(for: host),
            kSecAttrAccount as String: username,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw MqttConfigurationError.keychain(status)
        }

        return password
    }

    private static func saveMqttPassword(_ password: String, host: String, username: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: mqttKeychainServiceName(for: host),
            kSecAttrAccount as String: username,
        ]
        let data = Data(password.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)

        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw MqttConfigurationError.keychain(addStatus)
            }
        } else if status != errSecSuccess {
            throw MqttConfigurationError.keychain(status)
        }
    }

    private static func deleteMqttPassword(host: String, username: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: mqttKeychainServiceName(for: host),
            kSecAttrAccount as String: username,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MqttConfigurationError.keychain(status)
        }
    }

    private static func deleteAllStoredCredentials() throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let lookupStatus = SecItemCopyMatching(lookup as CFDictionary, &result)
        guard lookupStatus == errSecSuccess || lookupStatus == errSecItemNotFound else {
            throw DataResetError.keychain(lookupStatus)
        }
        guard lookupStatus == errSecSuccess else {
            return
        }

        let attributes: [[String: Any]]
        if let allAttributes = result as? [[String: Any]] {
            attributes = allAttributes
        } else if let singleAttributes = result as? [String: Any] {
            attributes = [singleAttributes]
        } else {
            attributes = []
        }

        let serviceNames = Set(attributes.compactMap { attributes in
            attributes[kSecAttrService as String] as? String
        }.filter(isOwnedKeychainService))

        for serviceName in serviceNames {
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
            ]
            let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
            guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                throw DataResetError.keychain(deleteStatus)
            }
        }
    }

    static func isOwnedKeychainService(_ serviceName: String) -> Bool {
        serviceName == keychainService
            || serviceName.hasPrefix("\(keychainService).")
            || serviceName == mqttKeychainService
            || serviceName.hasPrefix("\(mqttKeychainService).")
    }

    private static func mqttKeychainServiceName(for host: String) -> String {
        "\(mqttKeychainService).\(host.lowercased())"
    }

    private static func mqttEndpointScope(host: String, port: Int) -> String {
        "\(host.lowercased()):\(port)"
    }

    private static func normalizedServerAddress(_ address: String) -> String {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            return defaultServerAddress
        }

        let lowercasedAddress = trimmedAddress.lowercased()
        if lowercasedAddress.hasPrefix("http://") || lowercasedAddress.hasPrefix("https://") {
            return trimmedAddress.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        return "https://\(trimmedAddress.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
    }

    static func validatedServerAddress(_ address: String) throws -> String {
        let normalizedAddress = normalizedServerAddress(address)
        guard normalizedAddress != defaultServerAddress || !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServerAddressValidationError.empty
        }

        guard let schemeSeparatorRange = normalizedAddress.range(of: "://") else {
            throw ServerAddressValidationError.invalidURL
        }

        let scheme = String(normalizedAddress[..<schemeSeparatorRange.lowerBound]).lowercased()
        guard scheme == "http" || scheme == "https" else {
            throw ServerAddressValidationError.unsupportedScheme
        }

        let hostAndPort = String(normalizedAddress[schemeSeparatorRange.upperBound...])
        guard !hostAndPort.isEmpty,
              !hostAndPort.contains(where: { $0.isWhitespace }),
              !hostAndPort.contains("/"),
              !hostAndPort.contains("?"),
              !hostAndPort.contains("#"),
              !hostAndPort.contains("@") else {
            throw ServerAddressValidationError.invalidURL
        }

        let pieces = hostAndPort.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count <= 2 else {
            throw ServerAddressValidationError.invalidURL
        }

        guard let host = pieces.first, !host.isEmpty else {
            throw ServerAddressValidationError.missingHost
        }

        if pieces.count == 2 {
            guard let portText = pieces.last,
                  !portText.isEmpty,
                  portText.allSatisfy(\.isNumber),
                  let port = Int(portText),
                  (1...65535).contains(port) else {
                throw ServerAddressValidationError.invalidPort
            }
        }

        guard URL(string: normalizedAddress) != nil else {
            throw ServerAddressValidationError.invalidURL
        }

        return normalizedAddress
    }

    static func requiresInsecureTransportConfirmation(_ address: String) -> Bool {
        normalizedServerAddress(address).lowercased().hasPrefix("http://")
    }

    private static func validatedMqttHost(_ host: String) throws -> String {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw MqttConfigurationError.missingHost
        }
        guard !trimmedHost.contains(where: { $0.isWhitespace }),
              !trimmedHost.contains("://"),
              !trimmedHost.contains("/"),
              !trimmedHost.contains("?"),
              !trimmedHost.contains("#"),
              !trimmedHost.contains("@") else {
            throw MqttConfigurationError.invalidHost
        }

        let normalizedHost: String
        if trimmedHost.hasPrefix("[") || trimmedHost.hasSuffix("]") {
            guard trimmedHost.hasPrefix("["),
                  trimmedHost.hasSuffix("]"),
                  trimmedHost.count > 2 else {
                throw MqttConfigurationError.invalidHost
            }
            normalizedHost = String(trimmedHost.dropFirst().dropLast())
        } else {
            normalizedHost = trimmedHost
        }

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-:"))
        guard normalizedHost.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }),
              !normalizedHost.hasPrefix("."),
              !normalizedHost.hasSuffix("."),
              !normalizedHost.contains("..") else {
            throw MqttConfigurationError.invalidHost
        }

        if normalizedHost.contains(":") {
            // A single colon is a host-and-port separator, not a valid IPv6 address.
            guard normalizedHost.filter({ $0 == ":" }).count >= 2 else {
                throw MqttConfigurationError.invalidHost
            }
        }

        return normalizedHost.lowercased()
    }

    private static func validatedMqttTopicPrefix(_ topicPrefix: String) throws -> String {
        let normalizedPrefix = topicPrefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalizedPrefix.isEmpty,
              !normalizedPrefix.contains(where: { $0.isWhitespace || $0.isNewline }),
              !normalizedPrefix.contains("#"),
              !normalizedPrefix.contains("+"),
              !normalizedPrefix.contains("\0"),
              !normalizedPrefix.split(separator: "/", omittingEmptySubsequences: false).contains(where: \.isEmpty) else {
            throw MqttConfigurationError.missingTopicPrefix
        }

        return normalizedPrefix
    }

    private static func statusMessage(for error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain,
           let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlyingError.domain == NSPOSIXErrorDomain,
           underlyingError.code == 1 {
            return "Network blocked by sandbox. Enable Outgoing Connections."
        }

        if nsError.domain == NSURLErrorDomain {
            return "\(error.localizedDescription) (\(nsError.code))"
        }

        return error.localizedDescription
    }
}

private struct MqttEnvelope<Payload: Decodable>: Decodable {
    let after: Payload?
}

struct FrigateEvent: Decodable, Identifiable, Hashable {
    let id: String
    let camera: String
    let label: String
    let subLabel: String?
    let startTime: TimeInterval
    let endTime: TimeInterval?
    let topScore: Double?

    var startedAt: Date {
        Date(timeIntervalSince1970: startTime)
    }

    var displayDescription: String {
        "\(displayLabel) on \(camera) at \(startedAt.formatted(date: .omitted, time: .shortened))"
    }

    var displayLabel: String {
        subLabel?.displayDetectionName ?? label.displayDetectionName
    }

    var confidenceDescription: String? {
        guard let topScore else {
            return nil
        }

        let percentage = topScore <= 1 ? topScore * 100 : topScore
        return "\(Int(min(max(percentage, 0), 100).rounded()))%"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case camera
        case label
        case subLabel = "sub_label"
        case startTime = "start_time"
        case endTime = "end_time"
        case topScore = "top_score"
    }
}

struct FrigateReviewItem: Decodable, Identifiable, Hashable {
    let id: String
    let camera: String
    let startTime: TimeInterval
    let endTime: TimeInterval?
    let severity: String
    let data: ReviewData

    var activityTime: TimeInterval {
        endTime ?? startTime
    }

    var activityDate: Date {
        Date(timeIntervalSince1970: activityTime)
    }

    var displayDescription: String {
        let objectDescription = data.bestObjectDescription
        return "\(objectDescription) on \(camera) at \(activityDate.formatted(date: .omitted, time: .shortened))"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case camera
        case startTime = "start_time"
        case endTime = "end_time"
        case severity
        case data
    }

    struct ReviewData: Decodable, Hashable {
        let objects: [String]
        let subLabels: [String]

        var objectNames: [String] {
            var seenNames = Set<String>()
            return (objects + subLabels).filter {
                seenNames.insert($0.normalizedDetectionName).inserted
            }
        }

        var bestObjectDescription: String {
            let names = objectNames.map(\.displayDetectionName)
            return names.isEmpty ? "activity" : names.joined(separator: ", ")
        }

        enum CodingKeys: String, CodingKey {
            case objects
            case subLabels = "sub_labels"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            objects = Self.decodeStringList(from: container, forKey: .objects)
            subLabels = Self.decodeStringList(from: container, forKey: .subLabels)
        }

        private static func decodeStringList(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) -> [String] {
            if let values = try? container.decode([String].self, forKey: key) {
                return values
            }

            if let keyedValues = try? container.decode([String: String].self, forKey: key) {
                return Array(keyedValues.values)
            }

            return []
        }
    }
}

private struct FrigateConfiguration: Decodable {
    let cameras: [String: Camera]

    struct Camera: Decodable {
        let live: Live?
    }

    struct Live: Decodable {
        let streams: [String: String]
    }
}

private extension String {
    var normalizedDetectionName: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var displayDetectionName: String {
        let normalizedName = trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedName.isEmpty ? "activity" : normalizedName.capitalized
    }
}
