//
//  FrigateMSEStreamView.swift
//  TixisBirdview
//  Created by/with/for Marcel Kühn on 23.07.26 with the help of Codex (GPT-5.6 Terra, Extra High reasoning).
//

import SwiftUI
import WebKit

struct FrigateMSEStreamView: NSViewRepresentable {
    let serverURL: URL?
    let cameraName: String
    let cookies: [HTTPCookie]
    let sessionID: UUID
    @Binding var errorMessage: String?
    let onAspectRatioChanged: (CGFloat) -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "frigateMSE")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        guard let serverURL else {
            errorMessage = "Enter a Frigate server address first."
            return
        }

        let loadID = "\(serverURL.absoluteString)|\(cameraName)|\(sessionID.uuidString)"
        guard context.coordinator.loadID != loadID else {
            return
        }

        context.coordinator.loadID = loadID
        errorMessage = nil
        context.coordinator.load(
            html: Self.html(serverURL: serverURL, cameraName: cameraName),
            baseURL: serverURL,
            cookies: cookies,
            in: webView
        )
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "frigateMSE")
    }

    private static func html(serverURL: URL, cameraName: String) -> String {
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
            const codecs = ["avc1.640029", "avc1.64002A", "avc1.640033", "hvc1.1.6.L153.B0", "mp4a.40.2", "mp4a.40.5", "flac", "opus"];
            var socket;
            var mediaSource;
            var firstFrameTimer;
            let reconnectDelay = 2000;
            var shouldReconnect = true;

            function report(message) {
              window.webkit?.messageHandlers?.frigateMSE?.postMessage({ type: "error", message });
            }

            function connected() {
              window.webkit?.messageHandlers?.frigateMSE?.postMessage({ type: "connected" });
            }

            function reportAspectRatio() {
              if (video.videoWidth > 0 && video.videoHeight > 0) {
                window.webkit?.messageHandlers?.frigateMSE?.postMessage({
                  type: "aspectRatio",
                  value: video.videoWidth / video.videoHeight
                });
              }
            }

            video.addEventListener("click", () => {
              window.webkit?.messageHandlers?.frigateMSE?.postMessage({ type: "dismiss" });
            });

            video.addEventListener("loadeddata", () => {
              clearTimeout(firstFrameTimer);
              connected();
              reportAspectRatio();
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

            function start() {
              const MediaSourceConstructor = window.ManagedMediaSource || window.MediaSource;
              if (!MediaSourceConstructor) {
                report("This Mac cannot play Frigate's MSE stream.");
                return;
              }
              const supported = codecs.filter((codec) =>
                MediaSourceConstructor.isTypeSupported(`video/mp4; codecs="${codec}"`)
              ).join();
              if (!supported) {
                report("This Mac has no compatible Frigate video codec.");
                return;
              }

              const streamURL = new URL("/live/mse/api/ws", server);
              streamURL.protocol = streamURL.protocol === "https:" ? "wss:" : "ws:";
              streamURL.searchParams.set("src", camera);
              try {
                socket = new WebSocket(streamURL.href);
              } catch (error) {
                report(`Live stream connection failed: ${error.message || error}`);
                return;
              }
              socket.binaryType = "arraybuffer";

              socket.onopen = () => {
                mediaSource = new MediaSourceConstructor();
                mediaSource.addEventListener("sourceopen", () => {
                  socket.send(JSON.stringify({ type: "mse", value: supported }));
                }, { once: true });
                if ("ManagedMediaSource" in window) {
                  video.disableRemotePlayback = true;
                  video.srcObject = mediaSource;
                } else {
                  URL.revokeObjectURL(video.src || "");
                  video.src = URL.createObjectURL(mediaSource);
                  video.srcObject = null;
                }
                video.play().catch((error) => report(`Live stream could not start: ${error.message || error}`));
                clearTimeout(firstFrameTimer);
                firstFrameTimer = setTimeout(() => {
                  report("Frigate connected but did not send playable video.");
                }, 6000);
              };

              socket.onmessage = (event) => {
                if (typeof event.data === "string") {
                  let response;
                  try {
                    response = JSON.parse(event.data);
                  } catch (_) {
                    report("Frigate returned an invalid live-stream response.");
                    return;
                  }
                  if (response.type !== "mse") return;
                  try {
                    const sourceBuffer = mediaSource.addSourceBuffer(response.value);
                    if (sourceBuffer.mode) sourceBuffer.mode = "segments";
                    const pending = new Uint8Array(2 * 1024 * 1024);
                    let pendingLength = 0;

                    sourceBuffer.addEventListener("updateend", () => {
                      if (sourceBuffer.updating) return;

                      try {
                        if (pendingLength > 0) {
                          const data = pending.slice(0, pendingLength);
                          pendingLength = 0;
                          sourceBuffer.appendBuffer(data);
                        } else if (sourceBuffer.buffered.length) {
                          const start = sourceBuffer.buffered.start(0);
                          const end = sourceBuffer.buffered.end(sourceBuffer.buffered.length - 1) - 15;
                          if (end > start) sourceBuffer.remove(start, end);
                        }
                      } catch (_) {
                        // WebKit may transiently reject buffer maintenance.
                        // The following video segment will resume the update loop.
                      }
                    });

                    socket.onmessage = (binaryEvent) => {
                      if (typeof binaryEvent.data !== "string") {
                        if (sourceBuffer.updating || pendingLength > 0) {
                          const data = new Uint8Array(binaryEvent.data);
                          if (pendingLength + data.byteLength > pending.byteLength) {
                            report("Live stream buffer could not keep up. Retrying…");
                            socket.close();
                            return;
                          }
                          pending.set(data, pendingLength);
                          pendingLength += data.byteLength;
                        } else {
                          try {
                            sourceBuffer.appendBuffer(binaryEvent.data);
                          } catch (_) {
                            // The next segment will retry when WebKit is ready.
                          }
                        }
                      }
                    };
                  } catch (_) {
                    report("Frigate returned a video codec this Mac cannot play.");
                  }
                }
              };

              socket.onerror = () => report("Live stream connection failed.");
              socket.onclose = () => {
                clearTimeout(firstFrameTimer);
                report("Live stream disconnected. Retrying…");
                if (shouldReconnect) setTimeout(start, reconnectDelay);
              };
            }

            window.addEventListener("pagehide", () => {
              shouldReconnect = false;
              clearTimeout(firstFrameTimer);
              socket?.close();
            });
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
            case "dismiss":
                parent.onDismiss()
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
