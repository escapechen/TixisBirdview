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

        var errorDescription: String? {
            switch self {
            case .empty:
                "Enter a server address."
            case .invalidURL:
                "Enter a valid address, for example https://192.168.168.168."
            case .unsupportedScheme:
                "Use http:// or https://."
            case .missingHost:
                "Enter a host or IP address."
            case .invalidPort:
                "Use a numeric port from 1 to 65535."
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
    var availableClassificationNames: [String] = []
    var isLoadingClassifications = false
    var classificationLoadError: String?

    @ObservationIgnored var onOverlayVisibilityChanged: ((Bool) -> Void)?
    @ObservationIgnored var onConnectionStateChanged: ((ConnectionState) -> Void)?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var overlayDismissalTask: Task<Void, Never>?
    @ObservationIgnored private var seenEventIDs = Set<String>()
    @ObservationIgnored private var seenReviewItemIDs = Set<String>()
    @ObservationIgnored private var urlSession = FrigateMonitor.makeURLSession()
    @ObservationIgnored private var hasAuthenticatedSession = false
    @ObservationIgnored private var isLoadingLiveStreamNames = false
    @ObservationIgnored private var hasLoadedLiveStreamNames = false
    @ObservationIgnored private var alertSoundPlayer: NSSound?
    @ObservationIgnored private var lastAlertSoundDate: Date?
    @ObservationIgnored private var lastAutomaticPopupDate: Date?
    @ObservationIgnored private var lastAutomaticSoundDate: Date?

    private static let serverAddressKey = "serverAddress"
    private static let usernameKey = "serverUsername"
    private static let overlayDurationKey = "overlayDurationSeconds"
    private static let feedModeKey = "feedMode"
    private static let popupTriggerKey = "popupTrigger"
    private static let soundAlertEnabledKey = "soundAlertEnabled"
    private static let alertSoundKey = "alertSound"
    private static let soundAlertVolumeKey = "soundAlertVolume"
    private static let popupCooldownEnabledKey = "popupCooldownEnabled"
    private static let popupCooldownKey = "popupCooldownSeconds"
    private static let soundCooldownEnabledKey = "soundCooldownEnabled"
    private static let soundCooldownKey = "soundCooldownSeconds"
    private static let selectedClassificationsKey = "selectedClassificationNames"
    private static let defaultServerAddress = "https://192.168.168.168"
    private static let defaultOverlayDurationSeconds = 20.0
    private static let defaultSoundAlertVolume = 0.6
    private static let defaultCooldownSeconds = 60
    private static let defaultSelectedClassificationNames: Set<String> = ["bird", "cat", "bruno"]
    private static let keychainService = "org.tixisbirdview.app.frigate"

    init() {
        let savedOverlayDuration = UserDefaults.standard.double(forKey: Self.overlayDurationKey)
        overlayDurationSeconds = savedOverlayDuration > 0 ? savedOverlayDuration : Self.defaultOverlayDurationSeconds
        feedMode = FeedMode(rawValue: UserDefaults.standard.string(forKey: Self.feedModeKey) ?? "") ?? .jpeg
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
        availableClassificationNames = selectedClassificationNames.sorted()
    }

    var baseURL: URL? {
        URL(string: serverAddress)
    }

    var currentFeedCameraName: String {
        latestEvent?.camera ?? latestReviewItem?.camera ?? defaultFeedCameraName
    }

    var currentFeedStreamName: String {
        liveStreamNames[currentFeedCameraName] ?? currentFeedCameraName
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

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isMonitoring = false
        connectionState = .idle
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
    func applyServerAddress(_ address: String) -> Bool {
        applyConnectionSettings(address, username: username, password: "")
    }

    @discardableResult
    func applyConnectionSettings(
        _ address: String,
        username newUsername: String,
        password: String
    ) -> Bool {
        do {
            let validatedAddress = try Self.validatedServerAddress(address)
            try updateCredentials(username: newUsername, password: password)
            serverAddress = validatedAddress
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

        refreshLiveStreamNamesIfNeeded()

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

        let isNewItem = seenReviewItemIDs.insert(newestItem.id).inserted
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

        let isNewEvent = seenEventIDs.insert(newestEvent.id).inserted
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

    private func refreshLiveStreamNamesIfNeeded() {
        guard !isLoadingLiveStreamNames, !hasLoadedLiveStreamNames else {
            return
        }

        isLoadingLiveStreamNames = true
        Task { [weak self] in
            guard let self else {
                return
            }

            defer { isLoadingLiveStreamNames = false }

            do {
                liveStreamNames = try await fetchLiveStreamNames()
                hasLoadedLiveStreamNames = true
            } catch {
                // JPEG remains available if this optional live-stream lookup fails.
            }
        }
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
        guard !username.isEmpty, !hasAuthenticatedSession else {
            return
        }

        guard let password = try Self.savedPassword(for: username) else {
            throw AuthenticationError.missingPassword
        }
        guard let baseURL else {
            throw ServerAddressValidationError.invalidURL
        }

        let loginURL = baseURL.appending(path: "api/login")
        let body = try JSONSerialization.data(
            withJSONObject: ["user": username, "password": password]
        )
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

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

        let responseHeaders = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            guard let name = entry.key as? String, let value = entry.value as? String else {
                return
            }

            result[name] = value
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: responseHeaders, for: loginURL)
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

    private func updateCredentials(username newUsername: String, password: String) throws {
        let normalizedUsername = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousUsername = username

        if normalizedUsername.isEmpty {
            guard password.isEmpty else {
                throw AuthenticationError.passwordWithoutUsername
            }
            if !previousUsername.isEmpty {
                try Self.deletePassword(for: previousUsername)
            }
            username = ""
            return
        }

        if password.isEmpty {
            guard try Self.savedPassword(for: normalizedUsername) != nil else {
                throw AuthenticationError.missingPassword
            }
        } else {
            try Self.savePassword(password, for: normalizedUsername)
        }

        if previousUsername != normalizedUsername, !previousUsername.isEmpty {
            try Self.deletePassword(for: previousUsername)
        }
        username = normalizedUsername
    }

    private func resetAuthenticatedSession() {
        urlSession.invalidateAndCancel()
        urlSession = Self.makeURLSession()
        hasAuthenticatedSession = false
        hasLoadedLiveStreamNames = false
        liveStreamNames = [:]
        availableClassificationNames = []
        classificationLoadError = nil
        streamSessionID = UUID()
    }

    private static func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        return URLSession(configuration: configuration)
    }

    private static func savedPassword(for username: String) throws -> String? {
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
        guard status == errSecSuccess, let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw AuthenticationError.keychain(status)
        }

        return password
    }

    private static func savePassword(_ password: String, for username: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
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

    private static func deletePassword(for username: String) throws {
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

    private static func normalizedServerAddress(_ address: String) -> String {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            return defaultServerAddress
        }

        if trimmedAddress.hasPrefix("http://") || trimmedAddress.hasPrefix("https://") {
            return trimmedAddress.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        return "http://\(trimmedAddress.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
    }

    private static func validatedServerAddress(_ address: String) throws -> String {
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
            objects + subLabels
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
