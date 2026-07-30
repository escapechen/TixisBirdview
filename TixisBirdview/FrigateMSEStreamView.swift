//
//  FrigateMSEStreamView.swift
//  TixisBirdview
//  Created by/with/for Marcel Kühn on 23.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import SwiftUI
import WebKit

enum LiveStreamLatencyPolicy {
    /// Alert overlays favour freshness over smoothing through a weak connection.
    static let maximumBufferedSeconds = 1.5
    static let retainedBufferedSeconds = 0.75
    static let targetLatencySeconds = 0.35
    static let softCatchUpThresholdSeconds = 0.75
    static let hardCatchUpThresholdSeconds = 1.5
    static let maximumCatchUpPlaybackRate = 1.25
}

struct FrigateMSEStreamView: NSViewRepresentable {
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
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "frigateMSE")
    }

    private static func html(
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
          <video id="feed" autoplay muted playsinline></video>
          <script>
            const server = \(encodedServerURL);
            const camera = \(encodedCameraName);
            const video = document.getElementById("feed");
            const startupTimeoutMs = \(min(15, max(1, startupTimeoutSeconds)) * 1000);
            const debugEnabled = \(debugEnabled ? "true" : "false");
            const codecs = ["avc1.640029", "avc1.64002A", "avc1.640033", "hvc1.1.6.L153.B0", "mp4a.40.2", "mp4a.40.5", "flac", "opus"];
            const maxBufferSeconds = \(LiveStreamLatencyPolicy.maximumBufferedSeconds);
            const keepBufferSeconds = \(LiveStreamLatencyPolicy.retainedBufferedSeconds);
            const targetLatencySeconds = \(LiveStreamLatencyPolicy.targetLatencySeconds);
            const softCatchUpThresholdSeconds = \(LiveStreamLatencyPolicy.softCatchUpThresholdSeconds);
            const hardCatchUpThresholdSeconds = \(LiveStreamLatencyPolicy.hardCatchUpThresholdSeconds);
            const maximumCatchUpPlaybackRate = \(LiveStreamLatencyPolicy.maximumCatchUpPlaybackRate);
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
            var lastPlaybackTime = -1;
            var lastPlaybackAdvanceAt = Date.now();

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

            video.addEventListener("loadeddata", () => {
              clearTimeout(firstFrameTimer);
              firstFrameTimer = undefined;
              status("playing");
              debug("decoded first video frame");
              connected();
              reportAspectRatio();
              lastPlaybackTime = video.currentTime;
              lastPlaybackAdvanceAt = Date.now();
              clearTimeout(stablePlaybackTimer);
              stablePlaybackTimer = setTimeout(() => {
                if (Date.now() - lastPlaybackAdvanceAt < 5000) recoveryAttempts = 0;
              }, 10000);
            });

            video.addEventListener("loadedmetadata", reportAspectRatio);

            video.addEventListener("pause", () => {
              if (socket?.readyState === WebSocket.OPEN && !video.ended) {
                video.play().catch(() => {});
              }
            });

            window.addEventListener("error", (event) => {
              report(`Live stream error: ${event.message || "unknown JavaScript error"}`);
            });

            window.addEventListener("unhandledrejection", (event) => {
              report(`Live stream error: ${event.reason?.message || event.reason || "unknown error"}`);
            });

            function closeSocket() {
              if (!socket) return;
              socket.onopen = null;
              socket.onmessage = null;
              socket.onerror = null;
              socket.onclose = null;
              socket.close();
              socket = null;
            }

            function resetMediaSource() {
              sourceBuffer = null;
              mediaSource = null;
              pending = [];
              pendingBytes = 0;
              if (video.src) URL.revokeObjectURL(video.src);
              video.removeAttribute("src");
              video.srcObject = null;
              video.playbackRate = 1;
              video.load();
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
              status(`retrying (${recoveryAttempts})`);
              debug(`recovery attempt ${recoveryAttempts}`);
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
              keepNearLiveEdge();
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
              } catch (error) {
                recoverBufferError(error);
              }
            }

            function appendSegment(segment) {
              if (!sourceBuffer || isRecovering) return;
              pending.push(segment);
              pendingBytes += segment.byteLength;
              if (pendingBytes > maxPendingBytes) {
                recover("Live stream buffer could not keep up.");
                return;
              }
              pump();
            }

            function keepNearLiveEdge() {
              if (!sourceBuffer?.buffered.length || !Number.isFinite(video.currentTime)) return;
              const end = sourceBuffer.buffered.end(sourceBuffer.buffered.length - 1);
              const start = Math.max(0, end - maxBufferSeconds);
              const gap = end - video.currentTime;
              try {
                mediaSource?.setLiveSeekableRange?.(start, end);
              } catch (_) {
                // ManagedMediaSource availability differs across supported macOS releases.
              }
              if (gap > hardCatchUpThresholdSeconds) {
                video.currentTime = Math.max(0, end - targetLatencySeconds);
                video.playbackRate = 1;
              } else if (gap > softCatchUpThresholdSeconds) {
                video.playbackRate = Math.min(
                  maximumCatchUpPlaybackRate,
                  1 + (gap - targetLatencySeconds) * 0.2
                );
              } else if (video.playbackRate !== 1) {
                video.playbackRate = 1;
              }
            }

            function start() {
              if (!shouldReconnect) return;
              status("connecting");
              debug("opening MSE connection");
              const MediaSourceConstructor = window.ManagedMediaSource || window.MediaSource;
              if (!MediaSourceConstructor) {
                fallback("This Mac cannot play Frigate's MSE stream. Showing JPEG snapshots.");
                return;
              }
              const supported = codecs.filter((codec) =>
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
                if ("ManagedMediaSource" in window) {
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
                  recover("Frigate connected but did not send playable video.");
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
                      keepNearLiveEdge();
                      pump();
                    });

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
              if (video.currentTime > lastPlaybackTime + 0.05) {
                lastPlaybackTime = video.currentTime;
                lastPlaybackAdvanceAt = Date.now();
              }
              keepNearLiveEdge();
            });

            setInterval(() => {
              if (!shouldReconnect || !socket || socket.readyState !== WebSocket.OPEN || isRecovering) return;
              if (video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA
                  && Date.now() - lastPlaybackAdvanceAt > 5000) {
                recover("Live stream stalled.");
              }
            }, 2000);

            window.addEventListener("pagehide", () => {
              shouldReconnect = false;
              clearTimeout(firstFrameTimer);
              clearTimeout(socketOpenTimer);
              clearTimeout(restartTimer);
              clearTimeout(stablePlaybackTimer);
              closeSocket();
            });
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
