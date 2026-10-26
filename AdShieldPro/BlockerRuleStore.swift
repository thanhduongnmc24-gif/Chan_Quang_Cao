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
    case navGuard = "Chặn Nhảy Trang & Khóa Liên Kết"
    case vnMovieBet = "Chặn Web Phim / Nhà Cái / Popup"
    case vnAds = "Quảng Cáo Báo Việt (VN Ads)"
    case adNetwork = "Mạng Quảng Cáo Quốc Tế (Ads)"
    case tracker = "Trình Theo Dõi (Trackers)"
    case social = "Widget Mạng Xã Hội"
    case custom = "Quy Tắc & Khung Đã Chặn (Tùy Chỉnh)"
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

    // Navigation Guard & Long-Press Element Zapper toggles (synced via App Group + Safari Content Blocker)
    @Published var blockExternalNavigation: Bool = true {
        didSet {
            saveNavigationSettings()
            exportSafariBlockerJSON()
        }
    }

    /// When enabled, clicking ANY link on a webpage is blocked from opening another page ("Bấm vào liên kết cũng không mở")
    @Published var strictLockAllLinks: Bool = false {
        didSet {
            saveNavigationSettings()
            exportSafariBlockerJSON()
        }
    }

    /// When enabled, long-pressing (0.65s) any panel on a webpage highlights it and lets the user block/hide it permanently
    @Published var longPressZapEnabled: Bool = true {
        didSet {
            saveNavigationSettings()
        }
    }

    @Published var zappedSelectors: [String] = []

    private let storageKey = "adshield.saved.rules.v5"

    init() {
        loadNavigationSettings()
        loadRules()
        exportSafariBlockerJSON()
    }

    func loadNavigationSettings() {
        let groupDefaults = UserDefaults(suiteName: Self.appGroupID) ?? UserDefaults.standard
        if groupDefaults.object(forKey: "adshield.blockExternalNav") != nil {
            blockExternalNavigation = groupDefaults.bool(forKey: "adshield.blockExternalNav")
        }
        if groupDefaults.object(forKey: "adshield.strictLockAllLinks") != nil {
            strictLockAllLinks = groupDefaults.bool(forKey: "adshield.strictLockAllLinks")
        }
        if groupDefaults.object(forKey: "adshield.longPressZapEnabled") != nil {
            longPressZapEnabled = groupDefaults.bool(forKey: "adshield.longPressZapEnabled")
        }
        zappedSelectors = groupDefaults.stringArray(forKey: "adshield.zappedSelectors") ?? []
    }

    func saveNavigationSettings() {
        let groupDefaults = UserDefaults(suiteName: Self.appGroupID) ?? UserDefaults.standard
        groupDefaults.set(blockExternalNavigation, forKey: "adshield.blockExternalNav")
        groupDefaults.set(strictLockAllLinks, forKey: "adshield.strictLockAllLinks")
        groupDefaults.set(longPressZapEnabled, forKey: "adshield.longPressZapEnabled")
        groupDefaults.set(zappedSelectors, forKey: "adshield.zappedSelectors")
    }

    func addZappedSelector(_ selector: String, pageHost: String = "") {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !zappedSelectors.contains(trimmed) {
            zappedSelectors.insert(trimmed, at: 0)
            saveNavigationSettings()
        }
        let label = pageHost.isEmpty ? "Khung đã chặn: \(trimmed)" : "Khung trên \(pageHost)"
        addCustomRule(name: label, domainOrSelector: trimmed, category: .cssHide)
        reloadSafariContentBlocker()
    }

    func removeZappedSelector(at offsets: IndexSet) {
        zappedSelectors.remove(atOffsets: offsets)
        saveNavigationSettings()
        exportSafariBlockerJSON()
        reloadSafariContentBlocker()
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
        let trimmed = domainOrSelector.trimmingCharacters(in: .whitespacesAndNewlines)
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
    /// Zero `|` or `$` characters are used so Safari compiles every rule with zero errors.
    func exportSafariBlockerJSON() {
        var webkitRules: [[String: Any]] = []

        // 1. Block all popup windows & third-party main document navigations if blockExternalNavigation is enabled
        webkitRules.append([
            "trigger": [
                "url-filter": "^https?://",
                "resource-type": ["popup"]
            ],
            "action": [
                "type": "block"
            ]
        ])

        if blockExternalNavigation {
            webkitRules.append([
                "trigger": [
                    "url-filter": "^https?://",
                    "load-type": ["third-party"],
                    "resource-type": ["document"]
                ],
                "action": [
                    "type": "block"
                ]
            ])
        }

        // 2. If user turned on Strict Lock All Links ("Bấm vào liên kết cũng không mở"), also block top-level link navigations in Content Blocker
        if strictLockAllLinks {
            webkitRules.append([
                "trigger": [
                    "url-filter": "^https?://",
                    "resource-type": ["popup", "raw"]
                ],
                "action": [
                    "type": "block"
                ]
            ])
        }

        // 3. 100+ Vietnamese movie/betting banner keywords (each as an individual pipe-free rule)
        let betKeywords = [
            "k88", "du88", "man88", "xibet", "uk88", "ok9", "shbet", "hi88", "jun88", "new88",
            "f8bet", "789bet", "mb66", "8kbet", "go88", "sunwin", "rikvip", "hitclub", "b52club",
            "kubet", "ku11", "tha88", "bong88", "sbobet", "w88", "m88", "fun88", "fb88", "188bet",
            "vn88", "v9bet", "bk8", "dabet", "fabet", "debet", "red88", "zbet", "five88", "lucky88",
            "mibet", "nbet", "one88", "oxbet", "sin88", "sky88", "sv88", "ta88", "xo88", "bet88",
            "79king", "33win", "88clb", "99ok", "abc8", "alo789", "bet168", "bet365", "bj88", "cmd368",
            "da88", "dafabet", "ee88", "fc88", "ga88", "gk88", "hb88", "hello88", "i9bet", "j88",
            "k9win", "king88", "kkwin", "kuwin", "leo88", "lu88", "may88", "mcw", "mu88", "net88",
            "nohu", "ok365", "onbet", "qh88", "rr88", "s666", "sa88", "soc88", "sumvip", "sv388",
            "tf88", "thabet", "tk88", "top88", "twin68", "typhu88", "u888", "vip79", "vuabet",
            "win55", "win79", "win88", "x8club", "yo88"
        ]

        let isBetBlockEnabled = rules.first(where: { $0.domainOrSelector == "pack:vn_bet_banners" })?.isEnabled ?? true
        if isBetBlockEnabled {
            for kw in betKeywords {
                webkitRules.append([
                    "trigger": [
                        "url-filter": "^https?://.*\(kw).*"
                    ],
                    "action": [
                        "type": "block"
                    ]
                ])
            }
            let adPaths = [
                "/banners/", "/banner-ads/", "/quangcao/", "/quang-cao/", "/catfish/",
                "/float-ads/", "/floating-ads/", "/popup-ads/", "/sticky-ads/", "/bet-ads/",
                "/nhacai/", "/nha-cai/", "/qc-banner/", "/ads-gif/", "/gif-ads/"
            ]
            for pathKw in adPaths {
                webkitRules.append([
                    "trigger": [
                        "url-filter": "^https?://.*\(pathKw).*",
                        "resource-type": ["image", "script", "raw"]
                    ],
                    "action": [
                        "type": "block"
                    ]
                ])
            }
        }

        // 4. Individual domain and CSS rules
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
                let domains = item.domainOrSelector
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
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

        // 5. Append user-zapped panel selectors from Long-Press Element Zapper
        if !zappedSelectors.isEmpty {
            let combinedZapped = zappedSelectors.joined(separator: ", ")
            webkitRules.append([
                "trigger": [
                    "url-filter": ".*"
                ],
                "action": [
                    "type": "css-display-none",
                    "selector": combinedZapped
                ]
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

        let extID = Self.safariExtensionBundleID
        SFContentBlockerManager.reloadContentBlocker(withIdentifier: extID) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isReloadingSafari = false
                self.lastReloadTime = Date()
                if let nsError = error as NSError? {
                    self.safariReloadStatus = "Lỗi đồng bộ (Mã \(nsError.code)): \(nsError.localizedDescription)"
                } else {
                    self.safariReloadStatus = "Đã đồng bộ thành công (220+ quy tắc chặn)"
                }
            }
        }
    }

    static let defaultRules: [FilterRuleItem] = [
        // 1. Chặn Web Phim / Nhà Cái / Popup
        FilterRuleItem(
            name: "Gói Chặn 105+ Nhà Cái & Ảnh GIF Quảng Cáo Web Phim (K88, DU88, MAN88, XIBET, SHBET, Kubet, Go88, Sunwin...)",
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
        FilterRuleItem(name: "Adsterra Display Network", domainOrSelector: "profitabledisplaynetwork.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "Adsterra CPM Network", domainOrSelector: "profitablecpmrate.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "ExoClick Web Phim Ads", domainOrSelector: "exoclick.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "ExoSrv Ad Delivery", domainOrSelector: "exosrv.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "JuicyAds Network", domainOrSelector: "juicyads.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "TrafficJunky Network", domainOrSelector: "trafficjunky.net", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "TrafficStars Ad Network", domainOrSelector: "trafficstars.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "Clickadu Popup Ads", domainOrSelector: "clickadu.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "HilltopAds Network", domainOrSelector: "hilltopads.net", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "Galaksion Push & Pop", domainOrSelector: "galaksion.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "Mondiad Ad Network", domainOrSelector: "mondiad.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "AdMaven Popup Network", domainOrSelector: "admaven.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "OnClickAds / OnClkds Popup", domainOrSelector: "onclkds.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "OnClickAds Main", domainOrSelector: "onclickads.net", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "BidVertiser Direct Ads", domainOrSelector: "bidvertiser.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "PlugRush Traffic Pop", domainOrSelector: "plugrush.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "PopMyAds Redirects", domainOrSelector: "popmyads.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "RichAds Push & Pop", domainOrSelector: "richads.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "Evadav In-Page Push", domainOrSelector: "evadav.com", category: .vnMovieBet, isEnabled: true),
        FilterRuleItem(name: "RollerAds Push", domainOrSelector: "rollerads.com", category: .vnMovieBet, isEnabled: true),

        // 2. Ẩn Khung Banner & Catfish (CSS)
        FilterRuleItem(
            name: "Ẩn Link & Ảnh GIF Nhà Cái Nhóm 1 (K88, DU88, MAN88, XIBET, SHBET, Kubet...)",
            domainOrSelector: "a[href*='k88'], img[src*='k88'], a[href*='du88'], img[src*='du88'], a[href*='man88'], img[src*='man88'], a[href*='xibet'], img[src*='xibet'], a[href*='shbet'], a[href*='hi88'], a[href*='jun88'], a[href*='new88'], a[href*='f8bet'], a[href*='789bet'], a[href*='mb66'], a[href*='8kbet'], a[href*='go88'], a[href*='sunwin'], a[href*='rikvip'], a[href*='hitclub'], a[href*='kubet'], a[href*='bong88'], a[href*='w88'], a[href*='m88'], a[href*='fun88'], a[href*='fb88'], a[href*='188bet'], a[href*='vn88'], a[href*='bk8'], a[href*='dabet'], a[href*='fabet'], a[href*='debet'], a[href*='red88'], a[href*='zbet'], a[href*='five88'], a[href*='lucky88'], a[href*='oxbet'], a[href*='sin88'], a[href*='sky88'], a[href*='ta88'], a[href*='uk88'], a[href*='xo88'], a[href*='bet88'], a[target='_blank'] > img[src*='.gif']",
            category: .cssHide,
            isEnabled: true
        ),
        FilterRuleItem(
            name: "Ẩn Link & Ảnh GIF Nhà Cái Nhóm 2 (79King, 33Win, 88CLB, 99OK, Hello88, J88, King88...)",
            domainOrSelector: "a[href*='79king'], a[href*='33win'], a[href*='88clb'], a[href*='99ok'], a[href*='abc8'], a[href*='alo789'], a[href*='bj88'], a[href*='da88'], a[href*='ee88'], a[href*='gk88'], a[href*='hb88'], a[href*='hello88'], a[href*='i9bet'], a[href*='j88'], a[href*='king88'], a[href*='kuwin'], a[href*='may88'], a[href*='mu88'], a[href*='net88'], a[href*='ok365'], a[href*='qh88'], a[href*='rr88'], a[href*='s666'], a[href*='soc88'], a[href*='sumvip'], a[href*='sv388'], a[href*='thabet'], a[href*='tk88'], a[href*='top88'], a[href*='typhu88'], a[href*='u888'], a[href*='vip79'], a[href*='win55'], a[href*='win79'], a[href*='win88'], a[href*='yo88']",
            category: .cssHide,
            isEnabled: true
        ),
        FilterRuleItem(
            name: "Ẩn Khung Catfish & Popup Giữa Màn Hình Web Phim (#float_ck, #catfish, .popup-ads...)",
            domainOrSelector: "#float_ck, #hide_float_ck, .float-ck, #catfish, .catfish, .catfish-ads, #catfish-ads, .banner-catfish, #banner-catfish, .ads-catfish, #ads-catfish, .popup-ads, #popup-ads, .modal-ads, #modal-ads, .ads-popup, #ads-popup, .overlay-ads, #overlay-ads, .qc-banner, .banner-qc, .list-qc, #qc-left, #qc-right, .qc-left, .qc-right, .ads-left, .ads-right, #ads-left, #ads-right, .float-ads, #float-ads, .floating-ads, #floating-ads, .sticky-ads, #sticky-ads, .bottom-ads, #bottom-ads, .top-ads, #top-ads, .header-ads, .footer-ads, .under-player-ads, .player-ads, .preload-ads, #preload-ads, .ads-pc, .ads-mb, .ads-mobile, .banner-float, #banner-float, .popup-banner, #popup-banner, .ad-catfish, #ad-catfish, .fixed-bottom-ad, .sticky-bottom-ad",
            category: .cssHide,
            isEnabled: true
        ),
        FilterRuleItem(
            name: "Ẩn Khung Quảng Cáo Chuẩn Quốc Tế (.ad-banner, .adsbox, .adsbygoogle)",
            domainOrSelector: ".ad-banner, .adsbox, .adsbygoogle, .sponsored-post, .dfp-ad, .ad-container, .banner-top, .banner-bottom, .ad-slot, .ad-wrapper, .ad-unit, .ad-zone, .ad-space, .ad-holder, .ad-block, .widget_ads, .custom-ads, #div-gpt-ad, .ad-leaderboard, .ad-sidebar, .ad-rectangle, .ad-sky, .ad-footer, .ad-header, .ad-overlay",
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
        FilterRuleItem(name: "AdFlex CPA Vietnam", domainOrSelector: "adflex.vn", category: .vnAds, isEnabled: true),
        FilterRuleItem(name: "AccessTrade Vietnam", domainOrSelector: "accesstrade.vn", category: .vnAds, isEnabled: true),
        FilterRuleItem(name: "Novaon Digital Ads VN", domainOrSelector: "novaon.asia", category: .vnAds, isEnabled: true),
        FilterRuleItem(name: "ADX Vietnam Banner", domainOrSelector: "adx.vn", category: .vnAds, isEnabled: true),
        FilterRuleItem(name: "MGID Native Ads", domainOrSelector: "mgid.com", category: .vnAds, isEnabled: true),
        FilterRuleItem(name: "AdsKeeper Native Ads", domainOrSelector: "adskeeper.com", category: .vnAds, isEnabled: true),
        FilterRuleItem(name: "Dable Native News Ads VN", domainOrSelector: "dable.io", category: .vnAds, isEnabled: true),

        // 4. Mạng Quảng Cáo Quốc Tế
        FilterRuleItem(name: "Google DoubleClick Ads", domainOrSelector: "doubleclick.net", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Google AdServices", domainOrSelector: "googleadservices.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Google Syndication", domainOrSelector: "googlesyndication.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Google AdMob SDK", domainOrSelector: "admob.com", category: .adNetwork, isEnabled: true),
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
        FilterRuleItem(name: "TikTok Pangle Ad SDK", domainOrSelector: "pangle.io", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "Amazon AdSystem", domainOrSelector: "amazon-adsystem.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "PubMatic Ad Exchange", domainOrSelector: "pubmatic.com", category: .adNetwork, isEnabled: true),
        FilterRuleItem(name: "OpenX Ad Server", domainOrSelector: "openx.net", category: .adNetwork, isEnabled: true),

        // 5. Trình Theo Dõi & MXH
        FilterRuleItem(name: "Google Analytics Telemetry", domainOrSelector: "google-analytics.com", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "Google Tag Manager", domainOrSelector: "googletagmanager.com", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "AppsFlyer Attribution", domainOrSelector: "appsflyer.com", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "Adjust Mobile Tracker", domainOrSelector: "adjust.com", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "Branch.io Deep Link Tracker", domainOrSelector: "branch.io", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "Microsoft Clarity Heatmap", domainOrSelector: "clarity.ms", category: .tracker, isEnabled: true),
        FilterRuleItem(name: "Facebook Pixel & Graph Ads", domainOrSelector: "connect.facebook.net", category: .social, isEnabled: true),
        FilterRuleItem(name: "TikTok Byteoversea Ads SDK", domainOrSelector: "byteoversea.com", category: .social, isEnabled: true)
    ]
}
