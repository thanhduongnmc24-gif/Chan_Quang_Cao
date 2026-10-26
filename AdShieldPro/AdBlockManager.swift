import Foundation
import NetworkExtension
import SafariServices

struct DNSProviderOption: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let dohURL: String
    let serverIPs: [String]
    let badge: String
}

final class AdBlockManager: ObservableObject {
    @Published var isSystemDNSActive: Bool = false
    @Published var isSafariBlockerEnabled: Bool = false
    @Published var statusMessage: String = "Đang kiểm tra trạng thái bảo vệ..."
    @Published var selectedProvider: DNSProviderOption
    @Published var customDoHURL: String = ""
    @Published var excludedWiFiSSIDs: String = ""

    let providers: [DNSProviderOption] = [
        DNSProviderOption(
            id: "adguard_default",
            name: "AdGuard DNS (Khuyên dùng)",
            subtitle: "Chặn quảng cáo trong mọi ứng dụng, game, trình duyệt & chống theo dõi",
            dohURL: "https://dns.adguard-dns.com/dns-query",
            serverIPs: ["94.140.14.14", "94.140.15.15", "2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff"],
            badge: "Toàn diện"
        ),
        DNSProviderOption(
            id: "adguard_family",
            name: "AdGuard Family Protection",
            subtitle: "Chặn quảng cáo toàn hệ thống + chặn nội dung người lớn + tìm kiếm an toàn",
            dohURL: "https://family.adguard-dns.com/dns-query",
            serverIPs: ["94.140.14.15", "94.140.15.16", "2a10:50c0::bad1:ff", "2a10:50c0::bad2:ff"],
            badge: "Gia đình"
        ),
        DNSProviderOption(
            id: "mullvad_adblock",
            name: "Mullvad AdBlock DNS",
            subtitle: "Chặn quảng cáo & trình theo dõi với chính sách không lưu nhật ký (Zero-Log)",
            dohURL: "https://adblock.dns.mullvad.net/dns-query",
            serverIPs: ["194.242.2.3", "2a07:e340::3"],
            badge: "Riêng tư cao"
        ),
        DNSProviderOption(
            id: "controld_ads",
            name: "Control D (Block Ads & Trackers)",
            subtitle: "Tốc độ phản hồi cực nhanh, loại bỏ quảng cáo in-app và telemetry",
            dohURL: "https://freedns.controld.com/p2",
            serverIPs: ["76.76.2.2", "76.76.10.2", "2606:1a40::2", "2606:1a40:1::2"],
            badge: "Tốc độ cao"
        ),
        DNSProviderOption(
            id: "custom_doh",
            name: "NextDNS / AdGuard Private (Tùy chỉnh)",
            subtitle: "Nhập link DoH cá nhân (VD: https://dns.nextdns.io/abc123)",
            dohURL: "https://dns.nextdns.io/",
            serverIPs: ["45.90.28.0", "45.90.30.0"],
            badge: "Cá nhân hóa"
        )
    ]

    init() {
        self.selectedProvider = providers[0]
        refreshAllStates()
    }

    func refreshAllStates() {
        checkSystemDNSStatus()
        checkSafariContentBlockerStatus()
    }

    // MARK: - System-wide App Ad Blocking via NEDNSSettingsManager (DNS-over-HTTPS)
    func checkSystemDNSStatus() {
        let manager = NEDNSSettingsManager.shared()
        manager.loadFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.statusMessage = "Không thể đọc cấu hình DNS: \(error.localizedDescription)"
                    self.isSystemDNSActive = false
                    return
                }
                let active = (manager.dnsSettings != nil)
                self.isSystemDNSActive = active
                self.statusMessage = active
                    ? "Đang bật chặn quảng cáo toàn hệ thống (DoH)"
                    : "Chế độ chặn quảng cáo toàn hệ thống đang tắt"
            }
        }
    }

    func applySystemWideAdBlockDNS() {
        let manager = NEDNSSettingsManager.shared()
        manager.loadFromPreferences { [weak self] loadError in
            guard let self = self else { return }
            if let loadError = loadError {
                DispatchQueue.main.async {
                    self.statusMessage = "Lỗi tải Preferences: \(loadError.localizedDescription)"
                }
                return
            }

            let targetURLString: String
            if self.selectedProvider.id == "custom_doh", !self.customDoHURL.trimmingCharacters(in: .whitespaces).isEmpty {
                targetURLString = self.customDoHURL.trimmingCharacters(in: .whitespaces)
            } else {
                targetURLString = self.selectedProvider.dohURL
            }

            guard let dohURL = URL(string: targetURLString) else {
                DispatchQueue.main.async {
                    self.statusMessage = "URL DNS-over-HTTPS không hợp lệ"
                }
                return
            }

            let dohSettings = NEDNSOverHTTPSSettings(servers: self.selectedProvider.serverIPs)
            dohSettings.serverURL = dohURL

            manager.localizedDescription = "AdShield Pro - \(self.selectedProvider.name)"
            manager.dnsSettings = dohSettings

            // Optional Wi-Fi SSID exclusions
            var onDemandRules: [NEOnDemandRule] = []
            let ssids = self.excludedWiFiSSIDs
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if !ssids.isEmpty {
                let disconnectRule = NEOnDemandRuleEvaluateConnection()
                disconnectRule.interfaceTypeMatch = .wiFi
                disconnectRule.ssidMatch = ssids
                let ruleConnect = NEOnDemandRuleConnect()
                onDemandRules = [disconnectRule, ruleConnect]
            } else {
                let alwaysConnect = NEOnDemandRuleConnect()
                onDemandRules = [alwaysConnect]
            }
            manager.onDemandRules = onDemandRules

            manager.saveToPreferences { saveError in
                DispatchQueue.main.async {
                    if let saveError = saveError {
                        self.statusMessage = "Lưu DNS thất bại (Cần quyền Network Extension hoặc dùng bản .mobileconfig): \(saveError.localizedDescription)"
                        self.isSystemDNSActive = false
                    } else {
                        self.isSystemDNSActive = true
                        self.statusMessage = "Đã kích hoạt \(self.selectedProvider.name)! Vào Cài đặt > Cài đặt chung > Quản lý VPN & Thiết bị > DNS để chọn AdShield Pro nếu lần đầu bật."
                    }
                }
            }
        }
    }

    func disableSystemWideAdBlockDNS() {
        let manager = NEDNSSettingsManager.shared()
        manager.loadFromPreferences { [weak self] _ in
            manager.removeFromPreferences { removeError in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let removeError = removeError {
                        self.statusMessage = "Lỗi khi tắt DNS: \(removeError.localizedDescription)"
                    } else {
                        self.isSystemDNSActive = false
                        self.statusMessage = "Đã tắt bộ lọc DNS toàn hệ thống"
                    }
                }
            }
        }
    }

    // MARK: - Safari Content Blocker Check
    func checkSafariContentBlockerStatus() {
        SFContentBlockerManager.getStateOfContentBlocker(
            withIdentifier: BlockerRuleStore.safariExtensionBundleID
        ) { [weak self] state, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let state = state, error == nil {
                    self.isSafariBlockerEnabled = state.isEnabled
                } else {
                    self.isSafariBlockerEnabled = false
                }
            }
        }
    }

    // MARK: - Generate Signed/Installable .mobileconfig Profile (Fallback for Free Sideload / Unsigned IPA)
    func generateMobileConfigXML() -> String {
        let targetURL = (selectedProvider.id == "custom_doh" && !customDoHURL.isEmpty)
            ? customDoHURL
            : selectedProvider.dohURL
        let ipsXML = selectedProvider.serverIPs.map { "\t\t\t\t<string>\($0)</string>" }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>PayloadContent</key>
        \t<array>
        \t\t<dict>
        \t\t\t<key>DNSSettings</key>
        \t\t\t<dict>
        \t\t\t\t<key>DNSProtocol</key>
        \t\t\t\t<string>HTTPS</string>
        \t\t\t\t<key>ServerAddresses</key>
        \t\t\t\t<array>
        \(ipsXML)
        \t\t\t\t</array>
        \t\t\t\t<key>ServerURL</key>
        \t\t\t\t<string>\(targetURL)</string>
        \t\t\t</dict>
        \t\t\t<key>OnDemandRules</key>
        \t\t\t<array>
        \t\t\t\t<dict>
        \t\t\t\t\t<key>Action</key>
        \t\t\t\t\t<string>Connect</string>
        \t\t\t\t</dict>
        \t\t\t</array>
        \t\t\t<key>PayloadDescription</key>
        \t\t\t<string>Cấu hình DNS-over-HTTPS chặn quảng cáo toàn hệ thống từ AdShield Pro</string>
        \t\t\t<key>PayloadDisplayName</key>
        \t\t\t<string>AdShield Pro - \(selectedProvider.name)</string>
        \t\t\t<key>PayloadIdentifier</key>
        \t\t\t<string>com.adshield.pro.dns.\(selectedProvider.id)</string>
        \t\t\t<key>PayloadType</key>
        \t\t\t<string>com.apple.dnsSettings.managed</string>
        \t\t\t<key>PayloadUUID</key>
        \t\t\t<string>8B92E7A0-4D2C-4F9A-9D4A-100000000001</string>
        \t\t\t<key>PayloadVersion</key>
        \t\t\t<integer>1</integer>
        \t\t\t<key>ProhibitDisablement</key>
        \t\t\t<false/>
        \t\t</dict>
        \t</array>
        \t<key>PayloadDescription</key>
        \t<string>Chặn quảng cáo trên tất cả ứng dụng iOS và Safari thông qua DNS-over-HTTPS mã hóa.</string>
        \t<key>PayloadDisplayName</key>
        \t<string>AdShield Pro DNS (\(selectedProvider.name))</string>
        \t<key>PayloadIdentifier</key>
        \t<string>com.adshield.pro.profile</string>
        \t<key>PayloadOrganization</key>
        \t<string>AdShield Pro</string>
        \t<key>PayloadRemovalDisallowed</key>
        \t<false/>
        \t<key>PayloadType</key>
        \t<string>Configuration</string>
        \t<key>PayloadUUID</key>
        \t<string>8B92E7A0-4D2C-4F9A-9D4A-100000000000</string>
        \t<key>PayloadVersion</key>
        \t<integer>1</integer>
        </dict>
        </plist>
        """
    }
}
