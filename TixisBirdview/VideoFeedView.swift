//
//  VideoFeedView.swift
//  TixisBirdview
//
//  Created by/with/for Marcel Kühn on 22.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import AppKit
import SwiftUI

struct VideoFeedView: View {
    let monitor: FrigateMonitor
    var onAspectRatioChanged: (CGFloat) -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var frameImage: NSImage?
    @State private var frameTask: Task<Void, Never>?
    @State private var loadError: String?
    @State private var streamError: String?
    @State private var isUsingJPEGFallback = false
    @State private var isActivityBadgeVisible = false

    var body: some View {
        ZStack {
            content
            activityBadge
            overlayControls
        }
        .frame(minWidth: 240, minHeight: 150)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear {
            updateFeedMode()
            animateActivityBadge()
        }
        .onChange(of: monitor.feedMode) {
            isUsingJPEGFallback = false
            updateFeedMode()
        }
        .onChange(of: monitor.overlayPresentationID) {
            isUsingJPEGFallback = false
            updateFeedMode()
            animateActivityBadge()
        }
        .onChange(of: monitor.streamSessionID) {
            isUsingJPEGFallback = false
            updateFeedMode()
        }
        .onDisappear(perform: stopLoadingFrames)
    }

    @ViewBuilder
    private var content: some View {
        if showsJPEG {
            jpegContent
                .overlay(alignment: .center) {
                    if isUsingJPEGFallback {
                        Text("Live stream unavailable. Showing JPEG snapshots.")
                            .font(.callout)
                            .foregroundStyle(.white.secondary)
                            .multilineTextAlignment(.center)
                            .padding(12)
                            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding()
                    }
                }
        } else {
            let streamName = monitor.currentFeedStreamName
            FrigateMSEStreamView(
                serverURL: monitor.baseURL,
                cameraName: streamName,
                cookies: monitor.authenticationCookies(),
                sessionID: monitor.streamSessionID,
                errorMessage: $streamError,
                onAspectRatioChanged: onAspectRatioChanged,
                onDismiss: onDismiss,
                onFallbackToJPEG: switchToJPEGFallback
            )
            .id("\(monitor.serverAddress)|\(streamName)|\(monitor.streamSessionID.uuidString)")
            .overlay(alignment: .center) {
                if let streamError {
                    Text(streamError)
                        .font(.callout)
                        .foregroundStyle(.white.secondary)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding()
                }
            }
        }
    }

    @ViewBuilder
    private var jpegContent: some View {
        Group {
            if let frameImage {
                Image(nsImage: frameImage)
                    .resizable()
                    .scaledToFit()
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(loadError ?? "Loading \(monitor.currentFeedCameraName)")
                        .font(.callout)
                        .foregroundStyle(.white.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
    }

    private var overlayControls: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                        let remainingSeconds = monitor.overlayDismissalDate.map {
                            Int(ceil(max(0, $0.timeIntervalSince(timeline.date))))
                        } ?? 0

                        if remainingSeconds > 0 {
                            Text("\(remainingSeconds)s")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }

                    WindowZoomButton()
                        .frame(width: 32, height: 28)
                        .accessibilityLabel("Resize feed window")
                        .help("Resize feed window")

                    WindowDragHandle()
                        .frame(width: 32, height: 28)
                        .accessibilityLabel("Move feed window")
                        .help("Drag to move feed")
                }
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private var activityBadge: some View {
        VStack {
            HStack(alignment: .top) {
                if let activity = monitor.overlayActivity {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text(activity.title)
                                .font(.system(size: 18, weight: .bold))
                            if let confidence = activity.confidence {
                                Text(confidence)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.red.opacity(0.78), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Text(activity.detail)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.blue.opacity(0.7), in: Capsule())
                    }
                    .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
                }

                Spacer()
            }
            .padding(10)
            Spacer()
        }
        .allowsHitTesting(false)
        .offset(y: isActivityBadgeVisible ? 0 : -12)
        .opacity(isActivityBadgeVisible ? 1 : 0)
    }

    private func startLoadingFrames() {
        guard showsJPEG, frameTask == nil else {
            return
        }

        frameTask = Task {
            while !Task.isCancelled {
                await loadFrame()

                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    break
                }
            }
        }
    }

    private func stopLoadingFrames() {
        frameTask?.cancel()
        frameTask = nil
    }

    private func updateFeedMode() {
        if showsJPEG {
            streamError = nil
            startLoadingFrames()
        } else {
            stopLoadingFrames()
            frameImage = nil
            loadError = nil
            streamError = nil
        }
    }

    private var showsJPEG: Bool {
        monitor.feedMode == .jpeg || isUsingJPEGFallback
    }

    private func switchToJPEGFallback() {
        guard monitor.feedMode == .stream, !isUsingJPEGFallback else {
            return
        }

        isUsingJPEGFallback = true
        streamError = nil
        startLoadingFrames()
    }

    private func animateActivityBadge() {
        guard monitor.overlayActivity != nil else {
            isActivityBadgeVisible = true
            return
        }

        isActivityBadgeVisible = false
        guard !reduceMotion else {
            isActivityBadgeVisible = true
            return
        }

        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82).delay(0.08)) {
                isActivityBadgeVisible = true
            }
        }
    }

    private func loadFrame() async {
        do {
            let data = try await monitor.fetchLatestFrame()

            guard let image = NSImage(data: data) else {
                throw FeedError.invalidImage
            }

            frameImage = image
            reportAspectRatio(for: image)
            loadError = nil
        } catch {
            loadError = FeedError.displayMessage(for: error)
        }
    }

    private func reportAspectRatio(for image: NSImage) {
        let bitmapSize = image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .first
            .map { NSSize(width: $0.pixelsWide, height: $0.pixelsHigh) }
            ?? image.size

        guard bitmapSize.width > 0, bitmapSize.height > 0 else {
            return
        }

        onAspectRatioChanged(bitmapSize.width / bitmapSize.height)
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSButton {
        private var dragStartLocation: NSPoint?
        private var dragStartOrigin: NSPoint?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            configure(symbolName: "hand.draw.fill", label: "Move feed window")
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            configure(symbolName: "hand.draw.fill", label: "Move feed window")
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            dragStartLocation = NSEvent.mouseLocation
            dragStartOrigin = window?.frame.origin
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, let dragStartLocation, let dragStartOrigin else {
                return
            }

            let location = NSEvent.mouseLocation
            window.setFrameOrigin(
                NSPoint(
                    x: dragStartOrigin.x + location.x - dragStartLocation.x,
                    y: dragStartOrigin.y + location.y - dragStartLocation.y
                )
            )
        }

        override func mouseUp(with event: NSEvent) {
            dragStartLocation = nil
            dragStartOrigin = nil
        }
    }
}

private struct WindowZoomButton: NSViewRepresentable {
    func makeNSView(context: Context) -> ZoomView {
        ZoomView()
    }

    func updateNSView(_ nsView: ZoomView, context: Context) {}

    final class ZoomView: NSButton {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            configure(symbolName: "arrow.up.left.and.arrow.down.right", label: "Resize feed window")
            target = self
            action = #selector(zoomWindow)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            configure(symbolName: "arrow.up.left.and.arrow.down.right", label: "Resize feed window")
            target = self
            action = #selector(zoomWindow)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        @objc private func zoomWindow() {
            window?.zoom(nil)
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
        }
    }
}

private extension NSButton {
    func configure(symbolName: String, label: String) {
        title = ""
        isBordered = false
        imagePosition = .imageOnly
        image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: label
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        image?.isTemplate = true
        contentTintColor = .white.withAlphaComponent(0.9)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        layer?.cornerRadius = 6
        toolTip = label
        setAccessibilityLabel(label)
    }
}

private enum FeedError: Error {
    case httpStatus(Int)
    case invalidImage

    static func displayMessage(for error: Error) -> String {
        if let feedError = error as? FeedError {
            switch feedError {
            case .httpStatus(let statusCode):
                return "Feed returned HTTP \(statusCode)"
            case .invalidImage:
                return "Feed returned invalid image data"
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlyingError.domain == NSPOSIXErrorDomain,
           underlyingError.code == 1 {
            return "Network blocked by sandbox"
        }

        return "Feed unavailable"
    }
}
