//
//  SettingsMenuView.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 22.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import AppKit
import Observation
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case connection
    case feedAndSound
    case popupTriggers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection: "Connection"
        case .feedAndSound: "Feed & Sound"
        case .popupTriggers: "Popup Triggers"
        }
    }

    var systemImage: String {
        switch self {
        case .connection: "network"
        case .feedAndSound: "video"
        case .popupTriggers: "bell.badge"
        }
    }
}

@MainActor
@Observable
final class SettingsPaneSelection {
    var selected: SettingsPane

    init(selected: SettingsPane) {
        self.selected = selected
    }
}

struct SettingsMenuView: View {
    @Bindable var monitor: FrigateMonitor
    @Bindable var paneSelection: SettingsPaneSelection
    @State private var serverAddressDraft = ""
    @State private var usernameDraft = ""
    @State private var passwordDraft = ""
    @State private var mqttBrokerHostDraft = ""
    @State private var mqttBrokerPortDraft = 1883
    @State private var mqttUsesTLSDraft = false
    @State private var mqttUsernameDraft = ""
    @State private var mqttPasswordDraft = ""
    @State private var mqttTopicPrefixDraft = "frigate"
    @State private var classificationDraft = ""
    @State private var isClassificationPickerPresented = false
    @State private var classificationPickerSelections = Set<String>()
    var body: some View {
        VStack(spacing: 0) {
            settings
        }
        .onAppear {
            serverAddressDraft = monitor.serverAddress
            usernameDraft = monitor.username
            passwordDraft = ""
            mqttBrokerHostDraft = monitor.mqttBrokerHost
            mqttBrokerPortDraft = monitor.mqttBrokerPort
            mqttUsesTLSDraft = monitor.mqttUsesTLS
            mqttUsernameDraft = monitor.mqttUsername
            mqttPasswordDraft = ""
            mqttTopicPrefixDraft = monitor.mqttTopicPrefix
            monitor.refreshAvailableClassifications()
        }
    }

    private var settings: some View {
        ScrollView {
            Group {
                switch paneSelection.selected {
                case .connection:
                    connectionSettings
                case .feedAndSound:
                    feedAndSoundSettings
                case .popupTriggers:
                    popupTriggerSettings
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var connectionSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(title: "Frigate connection", systemImage: "video") {
                frigateConnectionSettings
            }

            settingsGroup(title: "Event delivery", systemImage: "bolt.horizontal.circle") {
                eventDeliverySettings
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var frigateConnectionSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Server")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("https://frigate.example.org:8971", text: $serverAddressDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            applySettings()
                        }

                    Button("Apply") {
                        applySettings()
                    }
                }

                if let serverAddressError = monitor.serverAddressError {
                    Label(serverAddressError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Frigate login (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Username", text: $usernameDraft)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $passwordDraft)
                    .textFieldStyle(.roundedBorder)

                Text("The password is stored in your macOS Keychain, not in UserDefaults.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var feedAndSoundSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(title: "Feed", systemImage: "video") {
                VStack(alignment: .leading, spacing: 10) {
                    Stepper(value: $monitor.overlayDurationSeconds, in: 5...120, step: 5) {
                        Text("Keep feed open: \(Int(monitor.overlayDurationSeconds)) seconds")
                    }

                    Picker("Feed", selection: $monitor.feedMode) {
                        ForEach(FrigateMonitor.FeedMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    Text(monitor.feedMode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if monitor.feedMode == .stream {
                        Stepper(value: $monitor.liveStartupTimeoutSeconds, in: 1...15) {
                            Text("Retry live player after: \(monitor.liveStartupTimeoutSeconds) seconds")
                        }
                        .help("JPEG stays visible while live video retries in the background. This is how long a live attempt gets to produce a frame before it reconnects.")

                        Text("JPEG starts loading immediately while live video connects.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Toggle("Write live-player diagnostics to terminal output", isOn: $monitor.isLiveDebugEnabled)
                            .help("Writes concise playback state transitions to the terminal where TixisBirdview was started. It excludes server addresses, camera names, credentials, cookies, and tokens.")
                    }
                }
            }

            settingsGroup(title: "Sound alerts", systemImage: "speaker.wave.2") {
                soundAlertSettings
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var popupTriggerSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(title: "Popup behavior", systemImage: "bell") {
                popupCooldownSettings
            }
            settingsGroup(title: "Classifications", systemImage: "line.3.horizontal.decrease.circle") {
                classificationSettings
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eventDeliverySettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Event delivery", selection: $monitor.eventDeliveryMode) {
                ForEach(FrigateMonitor.EventDeliveryMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Text(monitor.eventDeliveryMode.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if monitor.eventDeliveryMode == .mqtt {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("MQTT broker")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 8) {
                        TextField("Broker host", text: $mqttBrokerHostDraft)
                            .textFieldStyle(.roundedBorder)

                        TextField("Port", value: $mqttBrokerPortDraft, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                    }

                    Toggle("Use TLS", isOn: $mqttUsesTLSDraft)

                    Text("MQTT login (optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Username", text: $mqttUsernameDraft)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Password", text: $mqttPasswordDraft)
                        .textFieldStyle(.roundedBorder)

                    Text("Topic prefix")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("e.g. frigate", text: $mqttTopicPrefixDraft)
                        .textFieldStyle(.roundedBorder)

                    Text("MQTT credentials are stored in your macOS Keychain, separately for each broker.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Apply MQTT") {
                            applyMqttSettings()
                        }

                        Button("Verify") {
                            if applyMqttSettings() {
                                monitor.verifyMqttConnection()
                            }
                        }
                        .disabled(monitor.isMqttVerificationInProgress)

                        if monitor.isMqttVerificationInProgress {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let mqttVerificationStatus = monitor.mqttVerificationStatus {
                        Text(mqttVerificationStatus)
                            .font(.caption2)
                            .foregroundStyle(mqttVerificationStatus.contains("failed") || mqttVerificationStatus.contains("not applied") ? .red : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(monitor.eventDeliveryStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func settingsGroup<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var soundAlertSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Sound alert", isOn: $monitor.isSoundAlertEnabled)

            if monitor.isSoundAlertEnabled {
                HStack(spacing: 8) {
                    Picker("Sound", selection: $monitor.alertSound) {
                        ForEach(FrigateMonitor.AlertSound.allCases) { sound in
                            Text(sound.title).tag(sound)
                        }
                    }
                    .pickerStyle(.menu)

                    Button("Preview") {
                        monitor.previewSoundAlert()
                    }
                }

                HStack(spacing: 8) {
                    Text("Volume")
                    Slider(value: $monitor.soundAlertVolume, in: 0...1, step: 0.05)
                    Text("\(Int((monitor.soundAlertVolume * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                .font(.caption)

                soundCooldownSettings
            }
        }
    }

    private var popupCooldownSettings: some View {
        cooldownSettings(
            title: "Popup cooldown",
            isEnabled: $monitor.isPopupCooldownEnabled,
            seconds: $monitor.popupCooldownSeconds
        )
    }

    private var soundCooldownSettings: some View {
        cooldownSettings(
            title: "Sound cooldown",
            isEnabled: $monitor.isSoundCooldownEnabled,
            seconds: $monitor.soundCooldownSeconds
        )
    }

    private func cooldownSettings(
        title: String,
        isEnabled: Binding<Bool>,
        seconds: Binding<Int>
    ) -> some View {
        HStack(spacing: 8) {
            Toggle(title, isOn: isEnabled)

            if isEnabled.wrappedValue {
                TextField("Seconds", value: seconds, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Text("seconds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var classificationSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Popup for", selection: $monitor.popupTrigger) {
                ForEach(FrigateMonitor.PopupTrigger.allCases) { trigger in
                    Text(trigger.title).tag(trigger)
                }
            }

            Text(monitor.popupTrigger.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if monitor.popupTrigger == .selectedClassifications {
                HStack {
                    Text("Classifications")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        monitor.refreshAvailableClassifications()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(monitor.isLoadingClassifications)
                }

                if !selectedClassifications.isEmpty {
                    Text("Selected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    ForEach(selectedClassifications, id: \.self) { name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button {
                                monitor.setClassification(name, isSelected: false)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(name)")
                        }
                    }
                }

                if monitor.isLoadingClassifications {
                    ProgressView("Loading classifications…")
                        .controlSize(.small)
                } else if !availableClassifications.isEmpty {
                    HStack {
                        Text("Available in Frigate")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            classificationPickerSelections = []
                            isClassificationPickerPresented = true
                        } label: {
                            Label("Choose…", systemImage: "checklist")
                        }
                        .popover(isPresented: $isClassificationPickerPresented, arrowEdge: .trailing) {
                            classificationPicker
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("Add classification, e.g. Tixi", text: $classificationDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addClassification() }

                    Button("Add", action: addClassification)
                        .disabled(classificationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let classificationLoadError = monitor.classificationLoadError {
                    Label(classificationLoadError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func applySettings() {
        if monitor.applyConnectionSettings(
            serverAddressDraft,
            username: usernameDraft,
            password: passwordDraft
        ) {
            serverAddressDraft = monitor.serverAddress
            usernameDraft = monitor.username
            passwordDraft = ""
            monitor.refreshAvailableClassifications()
        }
    }

    @discardableResult
    private func applyMqttSettings() -> Bool {
        let didApply = monitor.applyMqttSettings(
            host: mqttBrokerHostDraft,
            port: mqttBrokerPortDraft,
            useTLS: mqttUsesTLSDraft,
            username: mqttUsernameDraft,
            password: mqttPasswordDraft,
            topicPrefix: mqttTopicPrefixDraft
        )

        guard didApply else {
            return false
        }

        mqttBrokerHostDraft = monitor.mqttBrokerHost
        mqttBrokerPortDraft = monitor.mqttBrokerPort
        mqttUsesTLSDraft = monitor.mqttUsesTLS
        mqttUsernameDraft = monitor.mqttUsername
        mqttPasswordDraft = ""
        mqttTopicPrefixDraft = monitor.mqttTopicPrefix
        return true
    }

    private func addClassification() {
        let classification = classificationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !classification.isEmpty else {
            return
        }

        monitor.setClassification(classification, isSelected: true)
        classificationDraft = ""
    }

    private var classificationPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose classifications")
                .font(.headline)

            Text("Select one or more labels to add.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(availableClassifications, id: \.self) { name in
                        Toggle(name, isOn: Binding(
                            get: { classificationPickerSelections.contains(name) },
                            set: { isSelected in
                                if isSelected {
                                    classificationPickerSelections.insert(name)
                                } else {
                                    classificationPickerSelections.remove(name)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(height: 220)

            HStack {
                Button("Cancel") {
                    isClassificationPickerPresented = false
                }

                Spacer()

                Button("Add selected (\(classificationPickerSelections.count))") {
                    for classification in classificationPickerSelections {
                        monitor.setClassification(classification, isSelected: true)
                    }
                    classificationPickerSelections = []
                    isClassificationPickerPresented = false
                }
                .disabled(classificationPickerSelections.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private var selectedClassifications: [String] {
        monitor.selectedClassificationNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var availableClassifications: [String] {
        monitor.availableClassificationNames.filter { !monitor.isClassificationSelected($0) }
    }
}

private extension FrigateMonitor.ConnectionState {
    var menuSystemImage: String {
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
}

#Preview {
    SettingsMenuView(
        monitor: FrigateMonitor(),
        paneSelection: SettingsPaneSelection(selected: .connection)
    )
}
