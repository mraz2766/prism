import Foundation
import WebKit

@MainActor
protocol WebRTCProbing: AnyObject, Sendable {
    func collect() async -> WebRTCReport
    func cancel()
}

/// WebRTC is a browser API: WebKit gathers real ICE candidates; Swift owns all state and UI.
/// No getUserMedia, remote page, audio, video, TURN credentials or private WebKit preferences.
@MainActor
final class WebRTCProbe: NSObject, WebRTCProbing, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<WebRTCReport, Never>?
    private var deadline: Task<Void, Never>?
    private var candidates: [ICECandidate] = []
    private var runID = UUID()

    func collect() async -> WebRTCReport {
        guard !Task.isCancelled else { return .init(outcome: .cancelled) }
        cancel()
        let id = UUID()
        runID = id
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                candidates = []
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = .nonPersistent()
                configuration.userContentController.add(self, name: "ice")
                let view = WKWebView(frame: .zero, configuration: configuration)
                view.navigationDelegate = self
                webView = view
                // An HTTPS origin gives the self-contained document a secure context; no page is fetched.
                view.loadHTMLString(Self.document, baseURL: URL(string: "https://prism.invalid/"))
                deadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                    guard let self, runID == id else { return }
                    finish(.timedOut)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.runID == id else { return }
                self.cancel()
            }
        }
    }

    func cancel() { finish(.cancelled) }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === webView, message.frameInfo.isMainFrame,
              let body = message.body as? [String: String] else { return }
        switch body["event"] {
        case "candidate":
            guard let address = body["address"], !address.isEmpty, address.count <= 256,
                  let kind = body["kind"], ["host", "srflx", "prflx", "relay"].contains(kind),
                  let transport = body["transport"] else { return }
            let candidate = ICECandidate(address: address, kind: kind, transport: transport)
            if !candidates.contains(where: { $0.id == candidate.id }), candidates.count < 64 { candidates.append(candidate) }
        case "complete": finish(.complete)
        case "timeout": finish(.timedOut)
        case "unavailable": finish(.unavailable)
        default: break
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        guard webView === self.webView else { return }
        finish(.unavailable)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        guard webView === self.webView else { return }
        finish(.unavailable)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        finish(.unavailable)
    }

    private func finish(_ outcome: WebRTCReport.Outcome) {
        guard let continuation else { return }
        self.continuation = nil
        deadline?.cancel()
        deadline = nil
        webView?.evaluateJavaScript("window.stopProbe && window.stopProbe()", completionHandler: nil)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "ice")
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        continuation.resume(returning: .init(candidates: candidates, outcome: outcome))
    }

    static let document = #"""
    <!doctype html><html><head><meta charset="utf-8"></head><body><script>
    (() => {
      const send = payload => window.webkit.messageHandlers.ice.postMessage(payload);
      let pc, timer, finished = false;
      window.stopProbe = () => { clearTimeout(timer); if (pc) pc.close(); };
      const finish = event => {
        if (finished) return;
        finished = true;
        window.stopProbe();
        send({ event });
      };
      try {
        if (typeof RTCPeerConnection !== 'function') return finish('unavailable');
        pc = new RTCPeerConnection({ iceServers: [
          { urls: 'stun:stun.cloudflare.com:3478' },
          { urls: 'stun:stun.l.google.com:19302' }
        ] });
        pc.onicecandidate = ({candidate: c}) => {
          if (finished) return;
          if (!c) return finish('complete');
          const parts = c.candidate.trim().split(/\s+/);
          const typeIndex = parts.indexOf('typ');
          send({ event: 'candidate', address: c.address || parts[4] || '',
                 kind: c.type || parts[typeIndex + 1] || '',
                 transport: c.protocol || (parts[2] || '').toLowerCase() });
        };
        pc.onicegatheringstatechange = () => { if (pc.iceGatheringState === 'complete') finish('complete'); };
        pc.createDataChannel('prism-ice-probe');
        timer = setTimeout(() => finish('timeout'), 7500);
        pc.createOffer().then(offer => pc.setLocalDescription(offer)).catch(() => finish('unavailable'));
      } catch (_) { finish('unavailable'); }
    })();
    </script></body></html>
    """#
}

@MainActor
final class PreviewWebRTCProbe: WebRTCProbing {
    func collect() async -> WebRTCReport {
        do { try await Task.sleep(for: .milliseconds(600)) } catch { return .init(outcome: .cancelled) }
        return .init(candidates: [.init(address: "preview.local", kind: "host", transport: "udp")])
    }
    func cancel() {}
}
