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
    @State private var classificationDraft = ""
    @State private var isClassificationPickerPresented = false
    @State private var classificationPickerSelections = Set<String>()

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

            Stepper(value: $monitor.overlayDurationSeconds, in: 5...120, step: 5) {
                Text("Keep feed open: \(Int(monitor.overlayDurationSeconds)) seconds")
            }

            soundAlertSettings

            Picker("Feed", selection: $monitor.feedMode) {
                ForEach(FrigateMonitor.FeedMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            Text(monitor.feedMode.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)

            classificationSettings
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
