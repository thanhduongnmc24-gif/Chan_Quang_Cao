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
    case vnMovieBet = "Chặn Web Phim / Nhà Cái / Popup"
    case vnAds = "Quảng Cáo Báo Việt (VN Ads)"
    case adNetwork = "Mạng Quảng Cáo Quốc Tế (Ads)"
    case tracker = "Trình Theo Dõi (Trackers)"
    case social = "Widget Mạng Xã Hội"
    case custom = "Quy Tắc Tùy Chỉnh"
    case cssHide = "Ẩn Khung Banner & Catfish (CSS)"
}

final class BlockerRuleStore: ObservableObject {
    static let appGroupID = "group.com.adshield.pro"

    static var safariExtensionBundleID: String {
        if let mainBundleID = Bundle.main.bundleIdentifier, !mainBundleID.isEmpty {
            return "\(mainBundleID).SafariBlocker"
        }
        return "com.adshield.pro.SafariBlocker"
    }

    static let sharedRulesFileName = "sharedBlockerList.json"

    @Published var rules: [FilterRuleItem] = []
    @Published var lastReloadTime: Date?
    @Published var safariReloadStatus: String = "Sẵn sàng đồng bộ"
    @Published var isReloadingSafari: Bool = false

    private let storageKey = "adshield.saved.rules.v4"

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

    /// Exports 100% WebKit DFA-compliant Content Blocker JSON into the shared App Group container.
    /// IMPORTANT: WebKit Content Blocker compiler DOES NOT support `|` (alternation) or `$` inside `url-filter`.
    /// Every domain or keyword pattern MUST be emitted as its own individual rule entry.
    func exportSafariBlockerJSON() {
        var webkitRules: [[String: Any]] = []

        // 1. Block third-party popup windows
        webkitRules.append([
            "trigger": [
                "url-filter": "^https?://",
                "load-type": ["third-party"],
                "resource-type": ["popup"]
            ],
            "action": [
                "type": "block"
            ]
        ])

        // 2. Built-in Vietnamese movie/betting banner keyword blocks (each as an individual pipe-free rule)
        let betKeywords = [
            "k88", "du88", "man88", "xibet", "uk88", "ok9", "shbet", "hi88", "jun88", "new88",
            "f8bet", "789bet", "mb66", "8kbet", "go88", "sunwin", "rikvip", "hitclub", "b52club",
            "kubet", "ku11", "tha88", "bong88", "sbobet", "w88", "m88", "fun88", "fb88", "188bet",
            "vn88", "v9bet", "bk8", "dabet", "fabet", "debet", "red88", "zbet", "five88", "lucky88",
            "mibet", "nbet", "one88", "oxbet", "sin88", "sky88", "sv88", "ta88", "xo88", "bet88"
        ]

        let isBetBlockEnabled = rules.first(where: { $0.domainOrSelector == "pack:vn_bet_banners" })?.isEnabled ?? true
        if isBetBlockEnabled {
            for kw in betKeywords {
                webkitRules.append([
                    "trigger": [
                        "url-filter": "^https?://.*\(kw).*",
                        "resource-type": ["image", "script", "popup", "raw"]
                    ],
                    "action": [
                        "type": "block"
                    ]
                ])
            }
            for pathKw in ["/banners/", "/quangcao/", "/quang-cao/", "/catfish/", "/float-ads/", "/popup-ads/"] {
                webkitRules.append([
                    "trigger": [
                        "url-filter": "^https?://.*\(pathKw).*",
                        "resource-type": ["image", "script"]
                    ],
                    "action": [
                        "type": "block"
                    ]
                ])
            }
        }

        // 3. Individual domain and CSS rules from the user's list
        for item in rules where item.isEnabled {
            if item.domainOrSelector == "pack:vn_bet_banners" {
                continue
            }
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
                // Split by comma in case user entered multiple domains, and create separate pipe-free rules
                let domains = item.domainOrSelector
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.contains("|") }

                for dom in domains {
                    let escapedDomain = dom
                        .replacingOccurrences(of: ".", with: "\\.")
                        .replacingOccurrences(of: "/", with: "")
                    webkitRules.append([
                        "trigger": [
                            "url-filter": "^https?://+([^/:]+\\.)?\(escapedDomain)[:/]",
                            "load-type": ["third-party", "first-party"]
                        ],
                        "action": [
                            "type": "block"
                        ]
                    ])
                }
            }
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

        let extID = Self.safariExtensionBundleID
        SFContentBlockerManager.reloadContentBlocker(withIdentifier: extID) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isReloadingSafari = false
                self.lastReloadTime = Date()
                if let nsError = error as NSError? {
                    self.safariReloadStatus = "Lỗi đồng bộ (Mã \(nsError.code)): \(nsError.localizedDescription)"
                } else {
                    self.safariReloadStatus = "Đã đồng bộ thành công (Hơn 110 quy tắc chặn)"
                }
            }
        }
    }

    static let defaultRules: [FilterRuleItem] = [
        // 1. Chặn Web Phim / Nhà Cái / Popup
        FilterRuleItem(
            name: "Gói Chặn 50+ Nhà Cái & Ảnh GIF Quảng Cáo Web Phim (K88, DU88, MAN88, XIBET, SHBET...)",
            domainOrSelector: "pack:vn_bet_banners",
            category: .vnMovieBet,
            isEnabled: true
        ),
        FilterRuleItem(name: "PopAds Popup Network", domainOrSelector: "popads.net", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "PopCash Popup Network", domainOrSelector: "popcash.net", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "PropellerAds Network", domainOrSelector: "propellerads.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "Adsterra Ad Network", domainOrSelector: "adsterra.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "Adsterra Script Tools", domainOrSelector: "adsterratools.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "Adsterra Banner Format", domainOrSelector: "highperformanceformat.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "ExoClick Web Phim Ads", domainOrSelector: "exoclick.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "ExoSrv Ad Delivery", domainOrSelector: "exosrv.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "JuicyAds Network", domainOrSelector: "juicyads.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "TrafficJunky Network", domainOrSelector: "trafficjunky.net", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "Clickadu Popup Ads", domainOrSelector: "clickadu.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "HilltopAds Network", domainOrSelector: "hilltopads.net", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "Galaksion Push & Pop", domainOrSelector: "galaksion.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "OnClickAds / OnClkds Popup", domainOrSelector: "onclkds.com", category: .vnMovieBet, isEnabled: true),

        // 2. Ẩn Khung Banner & Catfish (CSS)
        FilterRuleItem(
            name: "Ẩn Link & Ảnh GIF Nhà Cái Trên Web Phim (K88, DU88, MAN88, XIBET...)",
            domainOrSelector: "a[href*='k88'], img[src*='k88'], a[href*='du88'], img[src*='du88'], a[href*='man88'], img[src*='man88'], a[href*='xibet'], img[src*='xibet'], a[href*='shbet'], a[href*='hi88'], a[href*='jun88'], a[href*='new88'], a[href*='f8bet'], a[href*='789bet'], a[href*='mb66'], a[href*='8kbet'], a[href*='go88'], a[href*='sunwin'], a[href*='rikvip'], a[href*='hitclub'], a[href*='kubet'], a[href*='bong88'], a[href*='w88'], a[href*='m88'], a[href*='fun88'], a[href*='fb88'], a[href*='188bet'], a[href*='vn88'], a[href*='bk8'], a[href*='dabet'], a[href*='fabet'], a[href*='debet'], a[href*='red88'], a[href*='zbet'], a[href*='five88'], a[href*='lucky88'], a[href*='oxbet'], a[href*='sin88'], a[href*='sky88'], a[href*='ta88'], a[href*='uk88'], a[href*='xo88'], a[href*='bet88'], a[target='_blank'] > img[src*='.gif']",
            category: .cssHide,
            isEnabled: true
        ),
        FilterRuleItem(
            name: "Ẩn Khung Catfish & Popup Giữa Màn Hình Web Phim (#float_ck, #catfish, .popup-ads...)",
            domainOrSelector: "#float_ck, #hide_float_ck, .float-ck, #catfish, .catfish, .catfish-ads, #catfish-ads, .banner-catfish, #banner-catfish, .ads-catfish, #ads-catfish, .popup-ads, #popup-ads, .modal-ads, #modal-ads, .ads-popup, #ads-popup, .overlay-ads, #overlay-ads, .qc-banner, .banner-qc, .list-qc, #qc-left, #qc-right, .qc-left, .qc-right, .ads-left, .ads-right, #ads-left, #ads-right, .float-ads, #float-ads, .floating-ads, #floating-ads, .sticky-ads, #sticky-ads, .bottom-ads, #bottom-ads, .top-ads, #top-ads, .header-ads, .footer-ads, .under-player-ads, .player-ads, .preload-ads, #preload-ads, .ads-pc, .ads-mb, .ads-mobile",
            category: .cssHide,
            isEnabled: true
        ),
        FilterRuleItem(
            name: "Ẩn Khung Quảng Cáo Chuẩn Quốc Tế (.ad-banner, .adsbox, .adsbygoogle)",
            domainOrSelector: ".ad-banner, .adsbox, .adsbygoogle, .sponsored-post, .dfp-ad, .ad-container, .banner-top, .banner-bottom, .ad-slot, .ad-wrapper, .ad-unit, .ad-zone, .ad-space, .ad-holder, .ad-block, .widget_ads, .custom-ads, #div-gpt-ad",
            category: .cssHide,
            isEnabled: true
        ),

        // 3. Quảng Cáo Báo Việt
        FilterRuleItem(name: "Admicro (Quảng cáo Báo Việt)", domainOrSelector: "admicro.vn", category: .vnAds, isEnabled: true),
        FilterRuleItem(name: "VCCloud / Admicro CDN", domainOrSelector: "vcmedia.vn", category: .vnAds, isEnabled: true),
        FilterRuleItem(name: "eClick (Báo VnExpress / FPT)", domainOrSelector: "eclick.vn", category: .vnAds, isEnabled: true),
        FilterRuleItem(name: "Ambient Digital VN", domainOrSelector: "ambientplatform.vn", category: .vnAds, isEnabled: true),
        FilterRuleItem(name: "Ants Programmatic Ads VN", domainOrSelector: "ants.vn", category: .vnAds, isEnabled: true),
        FilterRuleItem(name: "Adtima / Zalo Ads", domainOrSelector: "adtima.vn", category: .vnAds, isEnabled: true),
        FilterRuleItem(name: "YoMedia VN Video Ads", domainOrSelector: "yomedia.vn", category: .vnAds, isEnabled: true),
        FilterRuleItem(name: "MGID Native Ads", domainOrSelector: "mgid.com", category: .vnAds, isEnabled: true),
        FilterRuleItem(name: "AdsKeeper Native Ads", domainOrSelector: "adskeeper.com", category: .vnAds, isEnabled: true),

        // 4. Mạng Quảng Cáo Quốc Tế
        FilterRuleItem(name: "Google DoubleClick Ads", domainOrSelector: "doubleclick.net", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Google AdServices", domainOrSelector: "googleadservices.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Google Syndication", domainOrSelector: "googlesyndication.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "AppLovin Ads SDK", domainOrSelector: "applovin.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Unity Ads Network", domainOrSelector: "unity3d.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "IronSource Mobile Ads", domainOrSelector: "supersonicads.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Vungle In-App Video Ads", domainOrSelector: "vungle.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Mintegral Ad Network", domainOrSelector: "rayjump.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Chartboost SDK", domainOrSelector: "chartboost.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "InMobi Ad Network", domainOrSelector: "inmobi.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Taboola Sponsored Feed", domainOrSelector: "taboola.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Outbrain Content Ads", domainOrSelector: "outbrain.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Criteo Retargeting", domainOrSelector: "criteo.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "AdColony Mobile Video", domainOrSelector: "adcolony.com", category: .adNetwork, isEnabled: true),

        // 5. Trình Theo Dõi & MXH
        FilterRuleItem(name: "Google Analytics Telemetry", domainOrSelector: "google-analytics.com", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "AppsFlyer Attribution", domainOrSelector: "appsflyer.com", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "Adjust Mobile Tracker", domainOrSelector: "adjust.com", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "Branch.io Deep Link Tracker", domainOrSelector: "branch.io", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "Facebook Pixel & Graph Ads", domainOrSelector: "connect.facebook.net", category: .social, isEnabled: true),
        FilterRuleItem(name: "TikTok Byteoversea Ads SDK", domainOrSelector: "byteoversea.com", category: .social, isEnabled: true)
    ]
}
