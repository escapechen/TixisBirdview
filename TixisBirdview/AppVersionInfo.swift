//
//  AppVersionInfo.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 22.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import Foundation

enum AppVersionInfo {
    private static let runBuildNumberKey = "runBuildNumber"

    static func incrementRunBuildNumber() {
        let nextBuildNumber = runBuildNumber + 1
        UserDefaults.standard.set(nextBuildNumber, forKey: runBuildNumberKey)
    }

    static var displayVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var bundleBuildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var runBuildNumber: Int {
        let storedBuildNumber = UserDefaults.standard.integer(forKey: runBuildNumberKey)
        return max(storedBuildNumber, 0)
    }

    static var displayBuild: String {
        "\(bundleBuildNumber).\(runBuildNumber)"
    }
}
