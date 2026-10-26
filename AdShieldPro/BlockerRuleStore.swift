import Foundation
import SafariServices

struct FilterRuleItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var domainOrSelector: String
    var category: RuleCategory
    var isEnabled: Bool
}

enum RuleCategory: String, Codable, CaseIterable {
    case adNetwork = "Mạng Quảng Cáo (Ads)"
    case tracker = "Trình Theo Dõi (Trackers)"
    case social = "Widget Mạng Xã Hội"
    case custom = "Quy Tắc Tùy Chỉnh"
    case cssHide = "Ẩn Khung Banner (CSS)"
}

final class BlockerRuleStore: ObservableObject {
    static let appGroupID = "group.com.adshield.pro"
    static let safariExtensionBundleID = "com.adshield.pro.SafariBlocker"
    static let sharedRulesFileName = "sharedBlockerList.json"

    @Published var rules: [FilterRuleItem] = []
    @Published var lastReloadTime: Date?
    @Published var safariReloadStatus: String = "Chưa đồng bộ"
    @Published var isReloadingSafari: Bool = false

    private let storageKey = "adshield.saved.rules.v1"

    init() {
        loadRules()
        exportSafariBlockerJSON()
    }

    func loadRules() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([FilterRuleItem].self, from: data) {
            self.rules = decoded
            return
        }
        self.rules = Self.defaultRules
        saveRules()
    }

    func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        exportSafariBlockerJSON()
    }

    func toggleRule(_ item: FilterRuleItem) {
        guard let idx = rules.firstIndex(where: { $0.id == item.id }) else { return }
        rules[idx].isEnabled.toggle()
        saveRules()
    }

    func addCustomRule(name: String, domainOrSelector: String, category: RuleCategory) {
        let trimmed = domainOrSelector.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        let newRule = FilterRuleItem(
            name: name.isEmpty ? trimmed : name,
            domainOrSelector: trimmed,
            category: category,
            isEnabled: true
        )
        rules.insert(newRule, at: 0)
        saveRules()
    }

    func deleteRules(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        saveRules()
    }

    /// Exports WebKit Content Blocker JSON into the shared App Group container so SafariBlocker Extension can load it
    func exportSafariBlockerJSON() {
        var webkitRules: [[String: Any]] = []

        for item in rules where item.isEnabled {
            if item.category == .cssHide {
                webkitRules.append([
                    "trigger": [
                        "url-filter": ".*"
                    ],
                    "action": [
                        "type": "css-display-none",
                        "selector": item.domainOrSelector
                    ]
                ])
            } else {
                let escapedDomain = NSRegularExpression.escapedPattern(for: item.domainOrSelector)
                webkitRules.append([
                    "trigger": [
                        "url-filter": "^https?://([a-z0-9-]+\\.)*\(escapedDomain)(/|:|$)",
                        "load-type": ["third-party", "first-party"]
                    ],
                    "action": [
                        "type": "block"
                    ]
                ])
            }
        }

        // Ensure at least one valid rule exists for WebKit compiler
        if webkitRules.isEmpty {
            webkitRules.append([
                "trigger": ["url-filter": "^https?://example-nonexistent-ad-domain\\.invalid/"],
                "action": ["type": "block"]
            ])
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: webkitRules, options: [.prettyPrinted]) else {
            return
        }

        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            let fileURL = groupURL.appendingPathComponent(Self.sharedRulesFileName)
            try? jsonData.write(to: fileURL, options: .atomic)
        }
    }

    func reloadSafariContentBlocker() {
        isReloadingSafari = true
        exportSafariBlockerJSON()

        SFContentBlockerManager.reloadContentBlocker(withIdentifier: Self.safariExtensionBundleID) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isReloadingSafari = false
                self.lastReloadTime = Date()
                if let error = error {
                    self.safariReloadStatus = "Lỗi: \(error.localizedDescription)"
                } else {
                    self.safariReloadStatus = "Đã cập nhật (\(self.rules.filter(\.isEnabled).count) quy tắc)"
                }
            }
        }
    }

    static let defaultRules: [FilterRuleItem] = [
        FilterRuleItem(name: "Google DoubleClick Ads", domainOrSelector: "doubleclick.net", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Google AdServices", domainOrSelector: "googleadservices.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Google Syndication", domainOrSelector: "googlesyndication.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "AppLovin Ads SDK", domainOrSelector: "applovin.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Unity Ads Network", domainOrSelector: "unityads.unity3d.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "IronSource Mobile Ads", domainOrSelector: "supersonicads.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Vungle In-App Video Ads", domainOrSelector: "vungle.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Mintegral Ad Network", domainOrSelector: "rayjump.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Chartboost SDK", domainOrSelector: "chartboost.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "InMobi Ad Network", domainOrSelector: "inmobi.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Taboola Sponsored Feed", domainOrSelector: "taboola.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Outbrain Content Ads", domainOrSelector: "outbrain.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Criteo Retargeting", domainOrSelector: "criteo.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "AdColony Mobile Video", domainOrSelector: "adcolony.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "PopAds Network", domainOrSelector: "popads.net", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Google Analytics Telemetry", domainOrSelector: "google-analytics.com", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "AppsFlyer Attribution", domainOrSelector: "appsflyer.com", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "Adjust Mobile Tracker", domainOrSelector: "adjust.com", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "Branch.io Deep Link Tracker", domainOrSelector: "branch.io", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "Mixpanel Analytics", domainOrSelector: "mixpanel.com", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "Segment.io Telemetry", domainOrSelector: "segment.io", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "Hotjar Session Recording", domainOrSelector: "hotjar.com", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "ScorecardResearch Beacon", domainOrSelector: "scorecardresearch.com", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "Facebook Pixel & Graph Ads", domainOrSelector: "connect.facebook.net", category: .social, isEnabled: true),
        FilterRuleItem(name: "TikTok Byteoversea Ads SDK", domainOrSelector: "byteoversea.com", category: .social, isEnabled: true),
        FilterRuleItem(name: "Ẩn Khung Quảng Cáo Chung", domainOrSelector: ".ad-banner, .adsbox, .adsbygoogle, [id^='google_ads_'], .sponsored-post", category: .cssHide, isEnabled: true)
    ]
}
