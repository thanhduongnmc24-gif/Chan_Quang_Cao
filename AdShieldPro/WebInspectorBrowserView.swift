import SwiftUI
import WebKit

struct WebInspectorBrowserView: View {
    @EnvironmentObject var ruleStore: BlockerRuleStore

    @State private var urlInput: String = "https://vnexpress.net"
    @State private var currentHost: String = "vnexpress.net"
    @State private var toastMessage: String? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Top Control Strip: Link Lock & Long-Press Element Zapper Toggles
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.secondary)
                            TextField("Nhập địa chỉ web (VD: phimmoi...)", text: $urlInput, onCommit: {
                                normalizeAndLoad()
                            })
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.subheadline)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(10)

                        Button(action: normalizeAndLoad) {
                            Text("Đi")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }

                    // Quick Switches for Link Lock & Long-Press Panel Zapper
                    HStack(spacing: 10) {
                        Button(action: {
                            ruleStore.strictLockAllLinks.toggle()
                            ruleStore.reloadSafariContentBlocker()
                            showTempToast(
                                ruleStore.strictLockAllLinks
                                ? "🔒 Đã BẬT Khóa Liên Kết: Bấm vào link bất kỳ sẽ không mở trang!"
                                : "🔓 Đã TẮT Khóa Toàn Bộ Liên Kết (Vẫn chặn nhảy tab quảng cáo lạ)"
                            )
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: ruleStore.strictLockAllLinks ? "lock.fill" : "lock.open.fill")
                                Text(ruleStore.strictLockAllLinks ? "Đang Khóa Mọi Link" : "Khóa Mở Link")
                                    .font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(ruleStore.strictLockAllLinks ? Color.red : Color(.tertiarySystemBackground))
                            .foregroundColor(ruleStore.strictLockAllLinks ? .white : .primary)
                            .cornerRadius(8)
                        }

                        Button(action: {
                            ruleStore.longPressZapEnabled.toggle()
                            showTempToast(
                                ruleStore.longPressZapEnabled
                                ? "👆 Đã BẬT: Nhấn giữ 0.6s vào khung bất kỳ trên web để chặn!"
                                : "Đã tắt chế độ nhấn giữ xóa khung"
                            )
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "hand.tap.fill")
                                Text(ruleStore.longPressZapEnabled ? "Nhấn Giữ Chặn: BẬT" : "Nhấn Giữ Chặn: TẮT")
                                    .font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(ruleStore.longPressZapEnabled ? Color.green.opacity(0.25) : Color(.tertiarySystemBackground))
                            .foregroundColor(ruleStore.longPressZapEnabled ? .green : .secondary)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))

                ZStack(alignment: .bottom) {
                    AdBlockWebViewRepresentable(
                        urlString: $urlInput,
                        strictLockAllLinks: ruleStore.strictLockAllLinks,
                        blockExternalNav: ruleStore.blockExternalNavigation,
                        longPressZapEnabled: ruleStore.longPressZapEnabled,
                        zappedSelectors: ruleStore.zappedSelectors,
                        onSelectorZapped: { selector, host in
                            ruleStore.addZappedSelector(selector, pageHost: host)
                            showTempToast("✅ Đã chặn khung (\(selector)) và đồng bộ sang Safari!")
                        },
                        onBlockedNavigation: { blockedURL in
                            showTempToast("🛡️ Đã chặn mở trang: \(blockedURL)")
                        }
                    )

                    if let toast = toastMessage {
                        Text(toast)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.88))
                            .cornerRadius(12)
                            .padding(.bottom, 16)
                            .transition(.opacity)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Trình Duyệt Nhấn Giữ Chặn Panel")
        }
    }

    private func normalizeAndLoad() {
        var trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }
        urlInput = trimmed
    }

    private func showTempToast(_ msg: String) {
        withAnimation {
            toastMessage = msg
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation {
                if toastMessage == msg {
                    toastMessage = nil
                }
            }
        }
    }
}

struct AdBlockWebViewRepresentable: UIViewRepresentable {
    @Binding var urlString: String
    var strictLockAllLinks: Bool
    var blockExternalNav: Bool
    var longPressZapEnabled: Bool
    var zappedSelectors: [String]
    var onSelectorZapped: (String, String) -> Void
    var onBlockedNavigation: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "adshieldBridge")

        let scriptSource = Self.injectedInspectorScript()
        let userScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(userScript)

        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        // Push updated settings into active page JS
        let selectorsJSON = (try? String(data: JSONEncoder().encode(zappedSelectors), encoding: .utf8)) ?? "[]"
        let js = """
        window.__adshieldUpdateState && window.__adshieldUpdateState({
            strictLockAllLinks: \(strictLockAllLinks ? "true" : "false"),
            blockExternalNav: \(blockExternalNav ? "true" : "false"),
            longPressZapEnabled: \(longPressZapEnabled ? "true" : "false"),
            zappedSelectors: \(selectorsJSON)
        });
        """
        webView.evaluateJavaScript(js, completionHandler: nil)

        if let currentURL = webView.url?.absoluteString,
           let targetURL = URL(string: urlString),
           currentURL != targetURL.absoluteString,
           !webView.isLoading {
            if URL(string: currentURL)?.host != targetURL.host {
                webView.load(URLRequest(url: targetURL))
            }
        }
    }

    static func injectedInspectorScript() -> String {
        return """
        (function() {
            let state = {
                strictLockAllLinks: false,
                blockExternalNav: true,
                longPressZapEnabled: true,
                zappedSelectors: []
            };

            window.__adshieldUpdateState = function(newState) {
                state = Object.assign(state, newState || {});
                applyZappedCSS();
            };

            function applyZappedCSS() {
                if (!Array.isArray(state.zappedSelectors)) return;
                let styleEl = document.getElementById('__adshield_webview_css__');
                if (!styleEl) {
                    styleEl = document.createElement('style');
                    styleEl.id = '__adshield_webview_css__';
                    (document.head || document.documentElement).appendChild(styleEl);
                }
                const baseHide = ".ad-banner, .adsbox, .adsbygoogle, #float_ck, #hide_float_ck, #catfish, .catfish, .popup-ads, #popup-ads, a[href*='k88'], a[href*='du88'], a[href*='man88'], a[href*='xibet'], a[href*='shbet'], a[href*='kubet'], a[target='_blank'] > img[src*='.gif']";
                const allSelectors = [baseHide].concat(state.zappedSelectors).filter(Boolean).join(", ");
                styleEl.textContent = allSelectors + " { display: none !important; visibility: hidden !important; pointer-events: none !important; }";
            }

            // Override window.open
            window.open = function(url) {
                window.webkit.messageHandlers.adshieldBridge.postMessage({
                    type: 'blockedNav',
                    url: String(url || 'popup')
                });
                return null;
            };

            // Long-press 650ms element picker
            let pressTimer = null;
            let startX = 0, startY = 0;
            let longPressed = false;

            function buildSelector(el) {
                if (!el || el === document.body || el === document.documentElement) return null;
                if (el.id && !/^\\d/.test(el.id)) return '#' + CSS.escape(el.id);
                if (el.classList && el.classList.length > 0) {
                    const cls = Array.from(el.classList).filter(Boolean);
                    if (cls.length > 0) return el.tagName.toLowerCase() + '.' + cls.map(c => CSS.escape(c)).join('.');
                }
                let path = [], curr = el;
                while (curr && curr !== document.body && path.length < 4) {
                    let tag = curr.tagName.toLowerCase();
                    if (curr.parentElement) {
                        const sibs = Array.from(curr.parentElement.children).filter(c => c.tagName === curr.tagName);
                        if (sibs.length > 1) tag += ':nth-of-type(' + (sibs.indexOf(curr) + 1) + ')';
                    }
                    path.unshift(tag);
                    curr = curr.parentElement;
                }
                return path.join(' > ');
            }

            window.addEventListener('touchstart', function(e) {
                if (!state.longPressZapEnabled || !e.touches || e.touches.length !== 1) return;
                const t = e.touches[0];
                if (t.target && t.target.closest && t.target.closest('#__adshield_modal__')) return;
                startX = t.clientX;
                startY = t.clientY;
                longPressed = false;
                clearTimeout(pressTimer);
                pressTimer = setTimeout(function() {
                    const el = document.elementFromPoint(startX, startY);
                    if (!el || el === document.body || el === document.documentElement) return;
                    longPressed = true;
                    showZapPrompt(el);
                }, 650);
            }, { passive: true, capture: true });

            window.addEventListener('touchmove', function(e) {
                if (!e.touches || e.touches.length !== 1) return;
                if (Math.abs(e.touches[0].clientX - startX) > 12 || Math.abs(e.touches[0].clientY - startY) > 12) {
                    clearTimeout(pressTimer);
                }
            }, { passive: true, capture: true });

            window.addEventListener('touchend', function(e) {
                clearTimeout(pressTimer);
                if (longPressed) {
                    e.preventDefault();
                    e.stopPropagation();
                    longPressed = false;
                }
            }, { capture: true });

            function showZapPrompt(targetEl) {
                const prevOutline = targetEl.style.outline;
                targetEl.style.setProperty('outline', '3px dashed #ef4444', 'important');
                const selector = buildSelector(targetEl) || targetEl.tagName.toLowerCase();

                let modal = document.getElementById('__adshield_modal__');
                if (!modal) {
                    modal = document.createElement('div');
                    modal.id = '__adshield_modal__';
                    modal.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.6);z-index:2147483647;display:flex;align-items:center;justify-content:center;padding:20px;font-family:-apple-system,sans-serif;';
                    document.body.appendChild(modal);
                }
                modal.innerHTML = '<div style="background:#111827;color:#fff;border:1px solid #374151;border-radius:16px;padding:18px;width:100%;max-width:330px;">' +
                    '<div style="font-size:16px;font-weight:700;color:#10d499;margin-bottom:6px;">🛡️ Chặn Panel Này?</div>' +
                    '<div style="font-size:12px;color:#9ca3af;margin-bottom:8px;">Ẩn khung này ngay lập tức và đồng bộ quy tắc sang Safari:</div>' +
                    '<div style="font-size:11px;font-family:monospace;background:#1f2937;padding:6px 8px;border-radius:8px;margin-bottom:14px;word-break:break-all;">' + selector + '</div>' +
                    '<div style="display:flex;gap:8px;">' +
                        '<button id="__zap_cancel__" style="flex:1;padding:10px;border-radius:10px;border:1px solid #4b5563;background:transparent;color:#d1d5db;font-weight:600;">Hủy</button>' +
                        '<button id="__zap_parent__" style="flex:1;padding:10px;border-radius:10px;border:1px solid #f59e0b;background:rgba(245,158,11,0.18);color:#fbbf24;font-weight:600;">Khung Cha</button>' +
                        '<button id="__zap_ok__" style="flex:1;padding:10px;border-radius:10px;border:none;background:#ef4444;color:#fff;font-weight:700;">Chặn</button>' +
                    '</div>' +
                '</div>';
                modal.style.display = 'flex';

                document.getElementById('__zap_cancel__').onclick = function() {
                    targetEl.style.outline = prevOutline;
                    modal.style.display = 'none';
                };
                document.getElementById('__zap_parent__').onclick = function() {
                    targetEl.style.outline = prevOutline;
                    if (targetEl.parentElement && targetEl.parentElement !== document.body) {
                        showZapPrompt(targetEl.parentElement);
                    }
                };
                document.getElementById('__zap_ok__').onclick = function() {
                    targetEl.style.setProperty('display', 'none', 'important');
                    targetEl.remove();
                    modal.style.display = 'none';
                    window.webkit.messageHandlers.adshieldBridge.postMessage({
                        type: 'zappedSelector',
                        selector: selector,
                        host: window.location.hostname
                    });
                };
            }

            document.addEventListener('DOMContentLoaded', applyZappedCSS);
        })();
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: AdBlockWebViewRepresentable

        init(_ parent: AdBlockWebViewRepresentable) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            if type == "zappedSelector", let sel = body["selector"] as? String {
                let host = (body["host"] as? String) ?? ""
                parent.onSelectorZapped(sel, host)
            } else if type == "blockedNav", let url = body["url"] as? String {
                parent.onBlockedNavigation(url)
            }
        }

        // Intercept new window / target="_blank" popup requests
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            let target = navigationAction.request.url?.host ?? "tab mới"
            parent.onBlockedNavigation(target)
            return nil
        }

        // Intercept link clicks when Strict Lock All Links or Block External Navigation is ON
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let reqURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if navigationAction.navigationType == .linkActivated {
                // 1. Strict Lock All Links: Clicking ANY link will NOT open another page
                if parent.strictLockAllLinks {
                    parent.onBlockedNavigation(reqURL.host ?? reqURL.absoluteString)
                    decisionHandler(.cancel)
                    return
                }

                // 2. Block External Domain Navigation
                if parent.blockExternalNav,
                   let currentHost = webView.url?.host?.replacingOccurrences(of: "www.", with: ""),
                   let targetHost = reqURL.host?.replacingOccurrences(of: "www.", with: ""),
                   currentHost != targetHost {
                    parent.onBlockedNavigation(targetHost)
                    decisionHandler(.cancel)
                    return
                }
            }

            decisionHandler(.allow)
        }
    }
}
