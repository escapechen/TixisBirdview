//
//  ContentView.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 22.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import SwiftUI

struct ContentView: View {
    @Bindable var monitor: FrigateMonitor
    let overlayController: OverlayWindowController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            statusGrid
            Divider()
            controls
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            overlayController.configure(with: monitor)
            monitor.start()
        }
        .onChange(of: monitor.shouldShowOverlay) { _, shouldShowOverlay in
            if shouldShowOverlay {
                overlayController.show()
            } else {
                overlayController.hide()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TixisBirdview")
                .font(.title2.weight(.semibold))

            Text("Monitoring birds, cats, and Bruno with \(monitor.currentFeedCameraName) at \(monitor.serverAddress)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var statusGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                Text("Status")
                    .foregroundStyle(.secondary)
                Label(monitor.connectionState.title, systemImage: monitor.connectionState.systemImage)
                    .foregroundStyle(monitor.connectionState.tint)
                    .lineLimit(nil)
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Last event")
                    .foregroundStyle(.secondary)
                Text(monitor.lastEventDescription)
                    .lineLimit(nil)
                    .textSelection(.enabled)
            }

            GridRow {
                Text("Overlay")
                    .foregroundStyle(.secondary)
                Text(monitor.shouldShowOverlay ? "Visible" : "Hidden")
            }
        }
        .font(.callout)
        .gridColumnAlignment(.leading)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                monitor.toggleMonitoring()
            } label: {
                Label(monitor.isMonitoring ? "Pause" : "Monitor", systemImage: monitor.isMonitoring ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)

            Button {
                monitor.showOverlayForLatestEvent()
            } label: {
                Label("Show Feed", systemImage: "rectangle.on.rectangle")
            }

            Button {
                monitor.dismissOverlay()
            } label: {
                Label("Hide", systemImage: "xmark")
            }
            .disabled(!monitor.shouldShowOverlay)
        }
    }
}

#Preview {
    ContentView(
        monitor: FrigateMonitor(),
        overlayController: OverlayWindowController()
    )
}
