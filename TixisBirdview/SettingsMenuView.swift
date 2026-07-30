//
//  SettingsMenuView.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 22.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import AppKit
import SwiftUI

struct SettingsMenuView: View {
    @Bindable var monitor: FrigateMonitor
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
    @State private var selectedSettingsTab = SettingsTab.connection

    private enum SettingsTab: Hashable {
        case connection
        case feedAndSound
        case popupTriggers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            settings
            Divider()
            status
            Divider()
            controls
        }
        .padding(16)
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

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: monitor.connectionState.menuSystemImage)
                .foregroundStyle(monitor.connectionState.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("TixisBirdview")
                    .font(.headline)
                Text(monitor.isMonitoring ? "Monitoring bird activity" : "Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var settings: some View {
        TabView(selection: $selectedSettingsTab) {
            ScrollView {
                connectionSettings
            }
            .tabItem {
                Label("Connection", systemImage: "network")
            }
            .tag(SettingsTab.connection)

            ScrollView {
                feedAndSoundSettings
            }
            .tabItem {
                Label("Feed & Sound", systemImage: "video")
            }
            .tag(SettingsTab.feedAndSound)

            ScrollView {
                popupTriggerSettings
            }
            .tabItem {
                Label("Popup Triggers", systemImage: "bell.badge")
            }
            .tag(SettingsTab.popupTriggers)
        }
    }

    private var connectionSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            eventDeliverySettings
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
    }

    private var feedAndSoundSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Feed")
                .font(.headline)

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
                .font(.caption2)
                .foregroundStyle(.secondary)

            if monitor.feedMode == .stream {
                Stepper(value: $monitor.liveStartupTimeoutSeconds, in: 1...15) {
                    Text("Retry live player after: \(monitor.liveStartupTimeoutSeconds) seconds")
                }
                .help("JPEG stays visible while live video retries in the background. This is how long a live attempt gets to produce a frame before it reconnects.")

                Text("JPEG starts loading immediately while live video connects.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Toggle("Write live-player diagnostics to terminal output", isOn: $monitor.isLiveDebugEnabled)
                    .help("Writes concise playback state transitions to the terminal where TixisBirdview was started. It excludes server addresses, camera names, credentials, cookies, and tokens.")
            }

            Divider()

            Text("Sound alerts")
                .font(.headline)

            soundAlertSettings
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
    }

    private var popupTriggerSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            popupCooldownSettings
            classificationSettings
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("MQTT broker")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("Broker host", text: $mqttBrokerHostDraft)
                            .textFieldStyle(.roundedBorder)

                        TextField("Port", value: $mqttBrokerPortDraft, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                    }

                    Toggle("Use TLS", isOn: $mqttUsesTLSDraft)

                    TextField("MQTT username (optional)", text: $mqttUsernameDraft)
                        .textFieldStyle(.roundedBorder)

                    SecureField("MQTT password", text: $mqttPasswordDraft)
                        .textFieldStyle(.roundedBorder)

                    TextField("Topic prefix, e.g. frigate", text: $mqttTopicPrefixDraft)
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
                .padding(.leading, 2)
            }
        }
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

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(monitor.connectionState.title, systemImage: monitor.connectionState.menuSystemImage)
                .foregroundStyle(monitor.connectionState.tint)
                .lineLimit(3)
                .textSelection(.enabled)

            Text(monitor.lastEventDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var controls: some View {
        HStack {
            Button {
                monitor.toggleMonitoring()
            } label: {
                Label(monitor.isMonitoring ? "Pause" : "Start", systemImage: monitor.isMonitoring ? "pause.fill" : "play.fill")
            }

            Button {
                monitor.showOverlayForLatestEvent()
            } label: {
                Label("Show Feed", systemImage: "rectangle.on.rectangle")
            }

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
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
    SettingsMenuView(monitor: FrigateMonitor())
}
