//
//  FrigateMSEStreamView.swift
//  TixisBirdview
//  Created by/with/for Marcel Kühn on 23.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import SwiftUI
import WebKit

enum LiveStreamLatencyPolicy {
    /// Keep enough complete media for WebKit to decode a camera GOP. Do not
    /// seek or alter playback speed: both can make WKWebView stop decoding.
    static let maximumBufferedSeconds = 6.0
    static let retainedBufferedSeconds = 5.0
    static let maximumBufferedGapBeforeRecoverySeconds = 8.0
    static let maximumConsecutiveRecoveryAttempts = 3

    static func shouldRecoverFromExcessiveLag(bufferedGap: Double) -> Bool {
        bufferedGap > maximumBufferedGapBeforeRecoverySeconds
    }
}

enum LiveStreamStartupPolicy {
    /// A camera may need to wait for its next H.264 keyframe after MSE has
    /// negotiated successfully. JPEG remains visible during this interval.
    static let minimumPlayableFrameWaitSeconds = 15

    static func playableFrameWaitSeconds(configuredSeconds: Int) -> Int {
        max(minimumPlayableFrameWaitSeconds, min(15, max(1, configuredSeconds)))
    }
}

struct FrigateMSEStreamView: NSViewRepresentable {
    static let teardownJavaScript = "window.tixisBirdviewStop?.();"

    let serverURL: URL?
    let cameraName: String
    let cookies: [HTTPCookie]
    let sessionID: UUID
    let isVideoVisible: Bool
    let startupTimeoutSeconds: Int
    let debugEnabled: Bool
    @Binding var errorMessage: String?
    let onAspectRatioChanged: (CGFloat) -> Void
    let onConnected: () -> Void
    let onFallbackToJPEG: () -> Void
    let onStatusChanged: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "frigateMSE")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.alphaValue = isVideoVisible ? 1 : 0.01
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        webView.alphaValue = isVideoVisible ? 1 : 0.01

        guard let serverURL else {
            errorMessage = "Enter a Frigate server address first."
            return
        }

        let loadID = "\(serverURL.absoluteString)|\(cameraName)|\(sessionID.uuidString)|\(startupTimeoutSeconds)|\(debugEnabled)"
        guard context.coordinator.loadID != loadID else {
            return
        }

        context.coordinator.loadID = loadID
        errorMessage = nil
        context.coordinator.load(
            html: Self.html(
                serverURL: serverURL,
                cameraName: cameraName,
                startupTimeoutSeconds: startupTimeoutSeconds,
                debugEnabled: debugEnabled
            ),
            baseURL: serverURL,
            cookies: cookies,
            in: webView
        )
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.evaluateJavaScript(Self.teardownJavaScript) { _, _ in
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)
        }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "frigateMSE")
    }

    static func html(
        serverURL: URL,
        cameraName: String,
        startupTimeoutSeconds: Int,
        debugEnabled: Bool
    ) -> String {
        let encodedServerURL = String(
            data: (try? JSONEncoder().encode(serverURL.absoluteString)) ?? Data("\"\"".utf8),
            encoding: .utf8
        )!
        let encodedCameraName = String(data: (try? JSONEncoder().encode(cameraName)) ?? Data("\"birdseye\"".utf8), encoding: .utf8)!

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>
            html, body, video { width: 100%; height: 100%; margin: 0; background: #000; overflow: hidden; }
            video { object-fit: contain; }
          </style>
        </head>
        <body>
          <video id="feed" autoplay muted playsinline preload="auto"></video>
          <script>
            const server = \(encodedServerURL);
            const camera = \(encodedCameraName);
            const video = document.getElementById("feed");
            const startupTimeoutMs = \(min(15, max(1, startupTimeoutSeconds)) * 1000);
            const debugEnabled = \(debugEnabled ? "true" : "false");
            // The alert player is intentionally muted. Requesting audio makes
            // WebKit synchronize video to camera audio timestamps and can turn
            // otherwise healthy live video into very slow playback.
            const videoCodecs = ["avc1.640029", "avc1.64002A", "avc1.640033", "hvc1.1.6.L153.B0"];
            // Frigate's own MSE player advertises these audio codecs as well.
            // Keep video-only as the low-latency default, but use the standard
            // set if go2rtc's video-only producer supplies only an initializer.
            const standardCodecs = [...videoCodecs, "mp4a.40.2", "mp4a.40.5", "flac", "opus"];
            const maxBufferSeconds = \(LiveStreamLatencyPolicy.maximumBufferedSeconds);
            const keepBufferSeconds = \(LiveStreamLatencyPolicy.retainedBufferedSeconds);
            const maximumBufferedGapBeforeRecoverySeconds = \(LiveStreamLatencyPolicy.maximumBufferedGapBeforeRecoverySeconds);
            const maxRecoveryAttempts = \(LiveStreamLatencyPolicy.maximumConsecutiveRecoveryAttempts);
            const playableFrameTimeoutMs = \(LiveStreamStartupPolicy.playableFrameWaitSeconds(configuredSeconds: startupTimeoutSeconds) * 1000);
            const maxPendingBytes = 2 * 1024 * 1024;
            const reconnectDelay = 1500;
            var socket;
            var mediaSource;
            var sourceBuffer;
            var pending = [];
            var pendingBytes = 0;
            var firstFrameTimer;
            var socketOpenTimer;
            var restartTimer;
            var stablePlaybackTimer;
            var shouldReconnect = true;
            var isRecovering = false;
            var recoveryAttempts = 0;
            var hasDecodedFirstFrame = false;
            var hasReportedPlaying = false;
            var playbackResumeInFlight = false;
            var useStandardCodecNegotiation = false;
            var lastPlaybackTime = -1;
            var lastPlaybackAdvanceAt = Date.now();
            var receivedSegments = 0;
            var appendedSegments = 0;
            var lastStats = {
              time: performance.now(), mediaTime: 0, received: 0, appended: 0, decoded: 0, dropped: 0
            };

            function report(message) {
              window.webkit?.messageHandlers?.frigateMSE?.postMessage({ type: "error", message });
            }

            function connected() {
              window.webkit?.messageHandlers?.frigateMSE?.postMessage({ type: "connected" });
            }

            function status(message) {
              window.webkit?.messageHandlers?.frigateMSE?.postMessage({ type: "status", message });
            }

            function debug(message) {
              if (debugEnabled) window.webkit?.messageHandlers?.frigateMSE?.postMessage({ type: "debug", message });
            }

            function debugPlaybackStats() {
              if (!debugEnabled) return;
              const now = performance.now();
              const elapsedSeconds = (now - lastStats.time) / 1000;
              if (elapsedSeconds < 2) return;
              const quality = video.getVideoPlaybackQuality?.();
              const decoded = quality?.totalVideoFrames ?? video.webkitDecodedFrameCount ?? 0;
              const dropped = quality?.droppedVideoFrames ?? video.webkitDroppedFrameCount ?? 0;
              const end = sourceBuffer?.buffered.length
                ? sourceBuffer.buffered.end(sourceBuffer.buffered.length - 1)
                : NaN;
              const gap = Number.isFinite(end) && Number.isFinite(video.currentTime)
                ? end - video.currentTime
                : NaN;
              const receivedRate = (receivedSegments - lastStats.received) / elapsedSeconds;
              const appendedRate = (appendedSegments - lastStats.appended) / elapsedSeconds;
              const decodedRate = (decoded - lastStats.decoded) / elapsedSeconds;
              const droppedRate = (dropped - lastStats.dropped) / elapsedSeconds;
              const mediaAdvance = video.currentTime - lastStats.mediaTime;
              debug(
                `stats source=${receivedRate.toFixed(1)}/s append=${appendedRate.toFixed(1)}/s ` +
                `decode=${decodedRate.toFixed(1)}/s drop=${droppedRate.toFixed(1)}/s ` +
                `gap=${Number.isFinite(gap) ? gap.toFixed(2) : "?"}s ` +
                `advance=${mediaAdvance.toFixed(2)}s pending=${pending.length}/${Math.round(pendingBytes / 1024)}KiB ` +
                `paused=${video.paused ? 1 : 0} ended=${video.ended ? 1 : 0} ready=${video.readyState} ` +
                `media=${mediaSource?.readyState || "none"}`
              );
              lastStats = {
                time: now, mediaTime: video.currentTime, received: receivedSegments,
                appended: appendedSegments, decoded, dropped
              };
            }

            function fallback(message) {
              debug("live player permanently unavailable");
              shouldReconnect = false;
              clearTimeout(firstFrameTimer);
              clearTimeout(socketOpenTimer);
              clearTimeout(restartTimer);
              clearTimeout(stablePlaybackTimer);
              closeSocket();
              resetMediaSource();
              window.webkit?.messageHandlers?.frigateMSE?.postMessage({ type: "fallback", message });
            }

            function reportAspectRatio() {
              if (video.videoWidth > 0 && video.videoHeight > 0) {
                window.webkit?.messageHandlers?.frigateMSE?.postMessage({
                  type: "aspectRatio",
                  value: video.videoWidth / video.videoHeight
                });
              }
            }

            function ensurePlayback(reason) {
              if (playbackResumeInFlight || socket?.readyState !== WebSocket.OPEN) return;
              const gap = bufferedGap();
              if (video.ended && (!Number.isFinite(gap) || gap <= 0.05)) {
                debug(`playback recovery after ${reason} deferred until fresh media arrives`);
                return;
              }
              const resumeTime = video.currentTime;
              playbackResumeInFlight = true;
              video.play()
                .then(() => {
                  if (video.currentTime + 0.5 < resumeTime) {
                    recover("Live stream timeline reset while resuming playback.");
                    return;
                  }
                  debug(`video resumed after ${reason}; ended=${video.ended ? 1 : 0}`);
                })
                .catch((error) => debug(`playback recovery after ${reason} failed: ${error.name || error}`))
                .finally(() => { playbackResumeInFlight = false; });
            }

            video.addEventListener("loadeddata", () => {
              clearTimeout(firstFrameTimer);
              firstFrameTimer = undefined;
              hasDecodedFirstFrame = true;
              debug("decoded first video frame");
              reportAspectRatio();
              if (lastPlaybackTime < 0) {
                lastPlaybackTime = video.currentTime;
                lastPlaybackAdvanceAt = Date.now();
              }
              if (video.paused) ensurePlayback("loaded data");
            });

            video.addEventListener("playing", () => {
              hasDecodedFirstFrame = true;
              status("playing");
              debug("video playback running");
              if (!hasReportedPlaying) {
                hasReportedPlaying = true;
                connected();
              }
              if (lastPlaybackTime < 0) {
                lastPlaybackTime = video.currentTime;
                lastPlaybackAdvanceAt = Date.now();
              }
              clearTimeout(stablePlaybackTimer);
              stablePlaybackTimer = setTimeout(() => {
                if (Date.now() - lastPlaybackAdvanceAt < 5000) recoveryAttempts = 0;
              }, 10000);
            });

            video.addEventListener("loadedmetadata", reportAspectRatio);
            video.addEventListener("waiting", () => debug("video waiting for decodable media"));
            video.addEventListener("stalled", () => debug("video element reported a network stall"));

            video.addEventListener("pause", () => {
              debug(
                `video paused ended=${video.ended ? 1 : 0} ready=${video.readyState} ` +
                `current=${video.currentTime.toFixed(2)} duration=${Number.isFinite(video.duration) ? video.duration.toFixed(2) : video.duration}`
              );
              ensurePlayback("pause");
            });
            video.addEventListener("ended", () => {
              debug("video reached its temporary buffered end; waiting for fresh media");
            });

            window.addEventListener("error", (event) => {
              report(`Live stream error: ${event.message || "unknown JavaScript error"}`);
            });

            window.addEventListener("unhandledrejection", (event) => {
              report(`Live stream error: ${event.reason?.message || event.reason || "unknown error"}`);
            });

            function closeSocket() {
              if (!socket) return;
              const currentSocket = socket;
              socket = null;
              currentSocket.onopen = null;
              currentSocket.onmessage = null;
              currentSocket.onerror = null;
              currentSocket.onclose = null;
              try {
                currentSocket.close();
              } catch (_) {
                // Closing a WebSocket that is still negotiating must not abort cleanup.
              }
            }

            function stop() {
              shouldReconnect = false;
              clearTimeout(firstFrameTimer);
              clearTimeout(socketOpenTimer);
              clearTimeout(restartTimer);
              clearTimeout(stablePlaybackTimer);
              closeSocket();
              resetMediaSource();
            }

            window.tixisBirdviewStop = stop;

            function resetMediaSource() {
              sourceBuffer = null;
              mediaSource = null;
              pending = [];
              pendingBytes = 0;
              receivedSegments = 0;
              appendedSegments = 0;
              lastPlaybackTime = -1;
              lastPlaybackAdvanceAt = Date.now();
              lastStats = {
                time: performance.now(), mediaTime: 0, received: 0, appended: 0, decoded: 0, dropped: 0
              };
              if (video.src) URL.revokeObjectURL(video.src);
              video.removeAttribute("src");
              video.srcObject = null;
              video.playbackRate = 1;
              hasDecodedFirstFrame = false;
              hasReportedPlaying = false;
              playbackResumeInFlight = false;
              video.load();
            }

            function waitForPlayableFrame() {
              clearTimeout(firstFrameTimer);
              firstFrameTimer = setTimeout(() => {
                if (receivedSegments <= 1 && !useStandardCodecNegotiation) {
                  useStandardCodecNegotiation = true;
                  recover("Frigate's video-only source delivered no media. Retrying with standard stream negotiation.");
                  return;
                }
                if (receivedSegments <= 1) {
                  recover("Frigate negotiated live video, but the configured go2rtc source delivered no media.");
                  return;
                }
                recover("Frigate delivered media fragments, but this Mac could not decode a playable frame.");
              }, playableFrameTimeoutMs);
            }

            function recover(reason) {
              if (!shouldReconnect || isRecovering) return;
              isRecovering = true;
              clearTimeout(firstFrameTimer);
              firstFrameTimer = undefined;
              clearTimeout(socketOpenTimer);
              socketOpenTimer = undefined;
              clearTimeout(stablePlaybackTimer);
              recoveryAttempts += 1;
              if (recoveryAttempts >= maxRecoveryAttempts) {
                fallback("Live video could not stay playable. Showing JPEG snapshots for this alert.");
                return;
              }
              status(`retrying (${recoveryAttempts})`);
              debug(`recovery attempt ${recoveryAttempts}: ${reason}`);
              report(`${reason} JPEG snapshots remain visible while live video retries.`);
              closeSocket();
              resetMediaSource();
              clearTimeout(restartTimer);
              restartTimer = setTimeout(() => {
                isRecovering = false;
                start();
              }, reconnectDelay);
            }

            function trimBuffer() {
              if (!sourceBuffer || sourceBuffer.updating || !sourceBuffer.buffered.length) return false;
              const ranges = sourceBuffer.buffered;
              const start = ranges.start(0);
              const end = ranges.end(ranges.length - 1);
              if (end - start <= maxBufferSeconds) return false;
              const removeEnd = Math.min(video.currentTime - 0.05, end - keepBufferSeconds);
              if (removeEnd <= start + 0.05) return false;
              sourceBuffer.remove(start, removeEnd);
              return true;
            }

            function recoverBufferError(error) {
              const name = error?.name || "UnknownError";
              if (name === "QuotaExceededError") {
                recover("Live stream buffer is full.");
              } else if (name === "InvalidStateError") {
                recover("Live stream buffer entered an invalid state.");
              } else {
                recover(`Live stream buffer error: ${name}.`);
              }
            }

            function pump() {
              if (!sourceBuffer || sourceBuffer.updating || isRecovering) return;
              try {
                if (trimBuffer()) return;
                if (!pending.length) return;
                const segment = pending.shift();
                pendingBytes -= segment.byteLength;
                sourceBuffer.appendBuffer(segment);
                appendedSegments += 1;
              } catch (error) {
                recoverBufferError(error);
              }
            }

            function appendSegment(segment) {
              if (!sourceBuffer || isRecovering) return;
              receivedSegments += 1;
              pending.push(segment);
              pendingBytes += segment.byteLength;
              if (pendingBytes > maxPendingBytes) {
                recover("Live stream buffer could not keep up.");
                return;
              }
              pump();
            }

            function bufferedGap() {
              if (!sourceBuffer?.buffered.length || !Number.isFinite(video.currentTime)) return NaN;
              return sourceBuffer.buffered.end(sourceBuffer.buffered.length - 1) - video.currentTime;
            }

            function keepMediaSourceOpenEnded() {
              if (!mediaSource || mediaSource.readyState !== "open" || sourceBuffer?.updating) return;
              try {
                if (mediaSource.duration !== Infinity) mediaSource.duration = Infinity;
              } catch (error) {
                debug(`could not keep live duration open-ended: ${error.name || error}`);
              }
            }

            function start() {
              if (!shouldReconnect) return;
              status("connecting");
              debug("opening MSE connection");
              // Match Frigate's Safari player: ManagedMediaSource is the native
              // WebKit path, with ordinary MediaSource as its compatibility fallback.
              const usingManagedMediaSource = !!window.ManagedMediaSource;
              const MediaSourceConstructor = usingManagedMediaSource
                ? window.ManagedMediaSource
                : window.MediaSource;
              if (!MediaSourceConstructor) {
                fallback("This Mac cannot play Frigate's MSE stream. Showing JPEG snapshots.");
                return;
              }
              debug(`using ${usingManagedMediaSource ? "ManagedMediaSource" : "MediaSource"}`);
              const requestedCodecs = useStandardCodecNegotiation ? standardCodecs : videoCodecs;
              debug(`requesting ${useStandardCodecNegotiation ? "standard" : "video-only"} codec negotiation`);
              const supported = requestedCodecs.filter((codec) =>
                MediaSourceConstructor.isTypeSupported(`video/mp4; codecs="${codec}"`)
              ).join();
              if (!supported) {
                fallback("This Mac has no compatible Frigate video codec. Showing JPEG snapshots.");
                return;
              }

              const streamURL = new URL("/live/mse/api/ws", server);
              streamURL.protocol = streamURL.protocol === "https:" ? "wss:" : "ws:";
              streamURL.searchParams.set("src", camera);
              let currentSocket;
              try {
                currentSocket = new WebSocket(streamURL.href);
                socket = currentSocket;
              } catch (error) {
                recover(`Live stream connection failed: ${error.message || error}`);
                return;
              }
              currentSocket.binaryType = "arraybuffer";
              clearTimeout(socketOpenTimer);
              socketOpenTimer = setTimeout(() => {
                if (socket === currentSocket && currentSocket.readyState !== WebSocket.OPEN) {
                  recover("Live stream connection timed out.");
                }
              }, startupTimeoutMs);

              currentSocket.onopen = () => {
                if (socket !== currentSocket || !shouldReconnect) return;
                clearTimeout(socketOpenTimer);
                socketOpenTimer = undefined;
                status("socket connected");
                mediaSource = new MediaSourceConstructor();
                mediaSource.addEventListener("sourceopen", () => {
                  try {
                    currentSocket.send(JSON.stringify({ type: "mse", value: supported }));
                  } catch (error) {
                    recover(`Live stream setup failed: ${error.message || error}`);
                  }
                }, { once: true });
                if (usingManagedMediaSource) {
                  video.disableRemotePlayback = true;
                  video.srcObject = mediaSource;
                } else {
                  URL.revokeObjectURL(video.src || "");
                  video.src = URL.createObjectURL(mediaSource);
                  video.srcObject = null;
                }
                video.play().catch((error) => recover(`Live stream could not start: ${error.message || error}`));
                clearTimeout(firstFrameTimer);
                firstFrameTimer = setTimeout(() => {
                  recover("Frigate connected but did not negotiate a live video format.");
                }, startupTimeoutMs);
              };

              currentSocket.onmessage = (event) => {
                if (socket !== currentSocket || isRecovering) return;
                if (typeof event.data === "string") {
                  let response;
                  try {
                    response = JSON.parse(event.data);
                  } catch (_) {
                    recover("Frigate returned an invalid live-stream response.");
                    return;
                  }
                  if (response.type !== "mse") return;
                  try {
                    if (!mediaSource || sourceBuffer) return;
                    debug(`Frigate announced ${response.value}`);
                    sourceBuffer = mediaSource.addSourceBuffer(response.value);
                    if (sourceBuffer.mode) sourceBuffer.mode = "segments";
                    sourceBuffer.addEventListener("updateend", () => {
                      keepMediaSourceOpenEnded();
                      if (video.paused) ensurePlayback("buffer update");
                      pump();
                      debugPlaybackStats();
                    });
                    waitForPlayableFrame();

                    currentSocket.onmessage = (binaryEvent) => {
                      if (socket !== currentSocket || isRecovering) return;
                      if (typeof binaryEvent.data !== "string") {
                        appendSegment(binaryEvent.data);
                      }
                    };
                  } catch (error) {
                    recover(`Frigate returned a video codec this Mac cannot play: ${error.name || error}`);
                  }
                }
              };

              currentSocket.onerror = () => recover("Live stream connection failed.");
              currentSocket.onclose = () => recover("Live stream disconnected.");
            }

            video.addEventListener("timeupdate", () => {
              if (lastPlaybackTime >= 0 && video.currentTime + 0.5 < lastPlaybackTime) {
                recover("Live stream timeline moved backwards.");
                return;
              }
              if (video.currentTime > lastPlaybackTime + 0.05) {
                lastPlaybackTime = video.currentTime;
                lastPlaybackAdvanceAt = Date.now();
              }
              debugPlaybackStats();
            });

            setInterval(() => {
              if (!shouldReconnect || !socket || socket.readyState !== WebSocket.OPEN || isRecovering) return;
              debugPlaybackStats();
              const gap = bufferedGap();
              if (hasDecodedFirstFrame && Number.isFinite(gap)
                  && gap > maximumBufferedGapBeforeRecoverySeconds) {
                recover("Live stream playback fell too far behind.");
                return;
              }
              if (video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA
                  && Date.now() - lastPlaybackAdvanceAt > 5000) {
                recover("Live stream stalled.");
              }
            }, 2000);

            window.addEventListener("pagehide", stop);
            status("starting player");
            start();
          </script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: FrigateMSEStreamView
        var loadID: String?

        init(parent: FrigateMSEStreamView) {
            self.parent = parent
        }

        func load(html: String, baseURL: URL, cookies: [HTTPCookie], in webView: WKWebView) {
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            cookieStore.getAllCookies { existingCookies in
                let work = DispatchGroup()

                for cookie in existingCookies {
                    work.enter()
                    cookieStore.delete(cookie) {
                        work.leave()
                    }
                }

                for cookie in cookies {
                    work.enter()
                    cookieStore.setCookie(cookie) {
                        work.leave()
                    }
                }

                work.notify(queue: .main) {
                    webView.loadHTMLString(html, baseURL: baseURL)
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }

            switch type {
            case "connected":
                parent.errorMessage = nil
                parent.onConnected()
            case "fallback":
                parent.errorMessage = body["message"] as? String
                parent.onFallbackToJPEG()
            case "status":
                if let status = body["message"] as? String {
                    parent.onStatusChanged(status)
                }
            case "debug":
                if let detail = body["message"] as? String {
                    print("TixisBirdview live: \(detail.prefix(300))")
                }
            case "aspectRatio":
                guard let value = body["value"] as? NSNumber else {
                    return
                }

                let aspectRatio = CGFloat(value.doubleValue)
                guard aspectRatio.isFinite, (0.25 ... 8).contains(aspectRatio) else {
                    return
                }

                parent.onAspectRatioChanged(aspectRatio)
            case "error":
                parent.errorMessage = body["message"] as? String
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.errorMessage = "Live stream could not load."
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.errorMessage = "Live stream could not load."
        }
    }
}
