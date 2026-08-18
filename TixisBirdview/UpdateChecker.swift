//
//  UpdateChecker.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 17.08.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import AppKit
import Foundation
import Observation

struct PublishedAppRelease: Equatable, Sendable {
    let version: String
    let pageURL: URL
}

struct AppSemanticVersion: Comparable, Equatable, Sendable {
    private let components: [Int]

    init?(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasPrefix("v") {
            normalized.removeFirst()
        }
        normalized = String(normalized.split(separator: "-", maxSplits: 1).first ?? "")

        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && Int($0) != nil }) else {
            return nil
        }

        var parsed = parts.compactMap { Int($0) }
        while parsed.count > 1, parsed.last == 0 {
            parsed.removeLast()
        }
        components = parsed
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

enum AppUpdatePolicy {
    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    static func isNewer(remoteVersion: String, than currentVersion: String) -> Bool {
        guard let remote = AppSemanticVersion(remoteVersion),
              let current = AppSemanticVersion(currentVersion) else {
            return false
        }
        return remote > current
    }

    static func shouldCheckAutomatically(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else {
            return true
        }
        return now.timeIntervalSince(lastCheck) >= automaticCheckInterval
    }
}

@MainActor
@Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(version: String)
        case updateAvailable(PublishedAppRelease)
        case noPublishedRelease
        case failed(message: String)
    }

    typealias ReleaseLoader = () async throws -> PublishedAppRelease?

    static let repositoryURL = URL(string: "https://github.com/escapechen/TixisBirdview")!
    static let releasesURL = repositoryURL.appending(path: "releases")

    private static let automaticallyChecksKey = "automaticallyChecksForUpdates"
    private static let lastAutomaticCheckKey = "lastAutomaticUpdateCheck"
    private static let lastNotifiedVersionKey = "lastNotifiedUpdateVersion"

    var state: State = .idle
    @ObservationIgnored var onUpdateAvailable: ((PublishedAppRelease) -> Void)?
    var automaticallyChecksForUpdates: Bool {
        didSet {
            defaults.set(automaticallyChecksForUpdates, forKey: Self.automaticallyChecksKey)
            if automaticallyChecksForUpdates {
                performAutomaticCheckIfNeeded(force: true)
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let currentVersion: String
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let releaseLoader: ReleaseLoader

    init(
        defaults: UserDefaults = .standard,
        currentVersion: String? = nil,
        now: @escaping () -> Date = Date.init,
        releaseLoader: @escaping ReleaseLoader = UpdateChecker.loadLatestGitHubRelease
    ) {
        self.defaults = defaults
        self.currentVersion = currentVersion ?? AppVersionInfo.displayVersion
        self.now = now
        self.releaseLoader = releaseLoader
        automaticallyChecksForUpdates = defaults.object(forKey: Self.automaticallyChecksKey) as? Bool ?? true
    }

    var isChecking: Bool {
        state == .checking
    }

    var availableRelease: PublishedAppRelease? {
        guard case let .updateAvailable(release) = state else {
            return nil
        }
        return release
    }

    var statusText: String {
        switch state {
        case .idle:
            "Checks GitHub Releases for newer stable versions."
        case .checking:
            "Checking for updates…"
        case let .upToDate(version):
            "TixisBirdview \(version) is up to date."
        case let .updateAvailable(release):
            "TixisBirdview \(release.version) is available."
        case .noPublishedRelease:
            "No published release is available yet."
        case let .failed(message):
            message
        }
    }

    var menuItemTitle: String {
        switch state {
        case let .updateAvailable(release):
            "Update to \(release.version)…"
        case .checking:
            "Checking for Updates…"
        default:
            "Check for Updates…"
        }
    }

    func performAutomaticCheckIfNeeded(force: Bool = false) {
        guard automaticallyChecksForUpdates, !isChecking else {
            return
        }

        let lastCheck = defaults.object(forKey: Self.lastAutomaticCheckKey) as? Date
        guard force || AppUpdatePolicy.shouldCheckAutomatically(lastCheck: lastCheck, now: now()) else {
            return
        }

        Task {
            await refresh(recordAutomaticCheck: true)
        }
    }

    func checkNow() {
        guard !isChecking else {
            return
        }
        Task {
            await refresh(recordAutomaticCheck: false)
        }
    }

    func checkAndPresentResult() {
        guard !isChecking else {
            return
        }
        Task {
            await refresh(recordAutomaticCheck: false)
            presentResult()
        }
    }

    func openAvailableRelease() {
        guard let availableRelease else {
            return
        }
        NSWorkspace.shared.open(availableRelease.pageURL)
    }

    func refresh(recordAutomaticCheck: Bool) async {
        guard !isChecking else {
            return
        }

        state = .checking
        if recordAutomaticCheck {
            defaults.set(now(), forKey: Self.lastAutomaticCheckKey)
        }

        do {
            guard let release = try await releaseLoader() else {
                state = .noPublishedRelease
                return
            }

            if AppUpdatePolicy.isNewer(remoteVersion: release.version, than: currentVersion) {
                state = .updateAvailable(release)
                if recordAutomaticCheck,
                   defaults.string(forKey: Self.lastNotifiedVersionKey) != release.version {
                    defaults.set(release.version, forKey: Self.lastNotifiedVersionKey)
                    onUpdateAvailable?(release)
                }
            } else {
                state = .upToDate(version: currentVersion)
            }
        } catch {
            state = .failed(message: "Couldn’t reach GitHub Releases. Check your internet connection and try again.")
        }
    }

    private func presentResult() {
        let alert = NSAlert()
        alert.alertStyle = .informational

        switch state {
        case let .updateAvailable(release):
            alert.messageText = "TixisBirdview \(release.version) Is Available"
            alert.informativeText = "You’re using version \(currentVersion). The release page contains the download and release notes."
            alert.addButton(withTitle: "View Release")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.pageURL)
            }
        case let .upToDate(version):
            alert.messageText = "You’re Up to Date"
            alert.informativeText = "TixisBirdview \(version) is the newest published version."
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        case .noPublishedRelease:
            alert.messageText = "No Published Release"
            alert.informativeText = "TixisBirdview does not have a published GitHub release yet."
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        case let .failed(message):
            alert.alertStyle = .warning
            alert.messageText = "Unable to Check for Updates"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        case .idle, .checking:
            break
        }
    }

    private static func loadLatestGitHubRelease() async throws -> PublishedAppRelease? {
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/escapechen/TixisBirdview/releases/latest")!,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TixisBirdview/\(AppVersionInfo.displayVersion)", forHTTPHeaderField: "User-Agent")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if httpResponse.statusCode == 404 {
            return nil
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        guard !payload.draft,
              !payload.prerelease,
              let pageURL = URL(string: payload.htmlURL),
              pageURL.scheme == "https",
              pageURL.host?.lowercased() == "github.com",
              pageURL.path.hasPrefix("/escapechen/TixisBirdview/releases/") else {
            throw URLError(.cannotParseResponse)
        }

        let version = payload.tagName.hasPrefix("v")
            ? String(payload.tagName.dropFirst())
            : payload.tagName
        guard AppSemanticVersion(version) != nil else {
            throw URLError(.cannotParseResponse)
        }
        return PublishedAppRelease(version: version, pageURL: pageURL)
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}
