import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var adBlockManager: AdBlockManager
    @EnvironmentObject var ruleStore: BlockerRuleStore

    @State private var selectedTab: Int = 0
    @State private var newRuleName: String = ""
    @State private var newRuleDomain: String = ""
    @State private var newRuleCategory: RuleCategory = .custom
    @State private var showAddRuleSheet: Bool = false

    var body: some View {
        TabView(selection: $selectedTab) {
            dashboardTab
                .tabItem {
                    Label("Bảo Vệ", systemImage: "shield.lefthalf.filled")
                }
                .tag(0)

            safariRulesTab
                .tabItem {
                    Label("Chặn Safari", systemImage: "safari.fill")
                }
                .tag(1)

            WebInspectorBrowserView()
                .tabItem {
                    Label("Nhấn Giữ Chặn", systemImage: "hand.tap.fill")
                }
                .tag(2)

            dnsConfigTab
                .tabItem {
                    Label("Chặn App (DNS)", systemImage: "network.badge.shield.half.filled")
                }
                .tag(3)

            guideTab
                .tabItem {
                    Label("Hướng Dẫn", systemImage: "book.closed.fill")
                }
                .tag(4)
        }
        .accentColor(Color(red: 0.06, green: 0.83, blue: 0.60))
        .onAppear {
            adBlockManager.refreshAllStates()
        }
    }

    // MARK: - Tab 1: Dashboard
    private var dashboardTab: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    // Hero Shield Card
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(
                                    adBlockManager.isSystemDNSActive
                                    ? Color.green.opacity(0.18)
                                    : Color.orange.opacity(0.15)
                                )
                                .frame(width: 100, height: 100)

                            Image(systemName: adBlockManager.isSystemDNSActive ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                                .font(.system(size: 50))
                                .foregroundColor(adBlockManager.isSystemDNSActive ? .green : .mint)
                        }

                        Text(adBlockManager.isSystemDNSActive ? "Đang Bảo Vệ Toàn Hệ Thống" : "Trung Tâm Chống Quảng Cáo")
                            .font(.title3.bold())

                        Text(adBlockManager.statusMessage)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        HStack(spacing: 12) {
                            Button(action: {
                                if adBlockManager.isSystemDNSActive {
                                    adBlockManager.disableSystemWideAdBlockDNS()
                                } else {
                                    adBlockManager.applySystemWideAdBlockDNS()
                                }
                            }) {
                                HStack {
                                    Image(systemName: adBlockManager.isSystemDNSActive ? "power" : "bolt.shield.fill")
                                    Text(adBlockManager.isSystemDNSActive ? "Tắt DNS Hệ Thống" : "Bật Chặn Mọi App (DNS)")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(adBlockManager.isSystemDNSActive ? Color.red.opacity(0.85) : Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }

                            Button(action: {
                                ruleStore.reloadSafariContentBlocker()
                                adBlockManager.refreshAllStates()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.headline)
                                    .padding(12)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(18)

                    // Quick Toggles for Navigation Lock & Long-Press Zapper
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.green)
                            Text("Chống Nhảy Trang & Nhấn Giữ Chặn Panel")
                                .font(.subheadline.bold())
                        }

                        Toggle(isOn: Binding(
                            get: { ruleStore.strictLockAllLinks },
                            set: { newVal in
                                ruleStore.strictLockAllLinks = newVal
                                ruleStore.reloadSafariContentBlocker()
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Khóa Mở Trang Khác (Strict Link Lock)")
                                    .font(.subheadline.weight(.semibold))
                                Text("Khi bật: Bấm vào bất kỳ liên kết nào trên trang cũng không mở trang mới")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        Toggle(isOn: Binding(
                            get: { ruleStore.blockExternalNavigation },
                            set: { newVal in
                                ruleStore.blockExternalNavigation = newVal
                                ruleStore.reloadSafariContentBlocker()
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Chặn Tự Động Nhảy Tab Quảng Cáo Lạ")
                                    .font(.subheadline.weight(.semibold))
                                Text("Chặn web phim tự mở tab nhà cái / Shopee / Lazada khi chạm màn hình")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        Toggle(isOn: $ruleStore.longPressZapEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Nhấn Giữ Vào Panel Trên Web Để Chặn")
                                    .font(.subheadline.weight(.semibold))
                                Text("Nhấn giữ 0.6 giây vào bất kỳ khung quảng cáo nào để xóa vĩnh viễn")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(16)

                    // Status Grid
                    HStack(spacing: 14) {
                        statusCard(
                            title: "App Khác (DNS)",
                            value: adBlockManager.isSystemDNSActive ? "Đang lọc" : "Đang tắt",
                            subtitle: adBlockManager.selectedProvider.name,
                            icon: "app.connected.to.app.below.fill",
                            color: adBlockManager.isSystemDNSActive ? .green : .gray
                        )

                        statusCard(
                            title: "Safari Blocker",
                            value: "220+ quy tắc",
                            subtitle: ruleStore.safariReloadStatus,
                            icon: "safari.fill",
                            color: .blue
                        )
                    }

                    // Quick Profile Fallback Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "doc.badge.gearshape.fill")
                                .foregroundColor(.mint)
                            Text("Xuất Cấu Hình DNS (.mobileconfig)")
                                .font(.subheadline.bold())
                        }
                        Text("Dành cho máy cài IPA qua chứng chỉ miễn phí (ESign, AltStore, Sideloadly): cài đặt trực tiếp cấu hình DNS-over-HTTPS vào Cài đặt iPhone.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: exportMobileConfigFile) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Cài Cấu Hình DNS Toàn Hệ Thống")
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.mint.opacity(0.2))
                            .foregroundColor(.mint)
                            .cornerRadius(10)
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("AdShield Pro")
        }
    }

    private func statusCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(value)
                .font(.headline.bold())
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - Tab 2: Safari Content Blocker Rules & Link Lock
    private var safariRulesTab: some View {
        NavigationView {
            List {
                Section(header: Text("Đồng Bộ & Trạng Thái Safari")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Đồng bộ quy tắc với Safari")
                                .font(.subheadline.bold())
                            Text(ruleStore.safariReloadStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: {
                            ruleStore.reloadSafariContentBlocker()
                        }) {
                            HStack(spacing: 6) {
                                if ruleStore.isReloadingSafari {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                Text("Cập nhật")
                                    .font(.caption.bold())
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(8)
                        }
                    }
                }

                Section(header: Text("Chặn Mở Trang Khác & Nhấn Giữ Xóa Khung")) {
                    Toggle(isOn: Binding(
                        get: { ruleStore.strictLockAllLinks },
                        set: { val in
                            ruleStore.strictLockAllLinks = val
                            ruleStore.reloadSafariContentBlocker()
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Khóa Mọi Liên Kết (Bấm Vào Link Không Mở)")
                                .font(.subheadline.weight(.medium))
                            Text("Chặn hoàn toàn việc mở sang trang khác khi bấm vào liên kết")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { ruleStore.blockExternalNavigation },
                        set: { val in
                            ruleStore.blockExternalNavigation = val
                            ruleStore.reloadSafariContentBlocker()
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Chặn Tự Động Nhảy Sang Trang Quảng Cáo Lạ")
                                .font(.subheadline.weight(.medium))
                            Text("Chặn popup và chặn mở tên miền bên thứ 3")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: $ruleStore.longPressZapEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nhấn Giữ (0.6s) Vào Panel Trên Web Để Chặn")
                                .font(.subheadline.weight(.medium))
                            Text("Hoạt động trên Safari (qua AdShield Web Guard) và tab Nhấn Giữ Chặn")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if !ruleStore.zappedSelectors.isEmpty {
                    Section(header: Text("Các Khung Panel Bạn Đã Nhấn Giữ Chặn (\(ruleStore.zappedSelectors.count))")) {
                        ForEach(ruleStore.zappedSelectors, id: \.self) { sel in
                            Text(sel)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.mint)
                        }
                        .onDelete(perform: ruleStore.removeZappedSelector)
                    }
                }

                ForEach(RuleCategory.allCases, id: \.self) { category in
                    let categoryRules = ruleStore.rules.filter { $0.category == category }
                    if !categoryRules.isEmpty {
                        Section(header: Text("\(category.rawValue) (\(categoryRules.count))")) {
                            ForEach(categoryRules) { rule in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(rule.name)
                                            .font(.subheadline.weight(.medium))
                                        Text(rule.domainOrSelector)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { rule.isEnabled },
                                        set: { _ in ruleStore.toggleRule(rule) }
                                    ))
                                    .labelsHidden()
                                }
                            }
                            .onDelete { offsets in
                                let toDeleteIDs = offsets.map { categoryRules[$0].id }
                                ruleStore.rules.removeAll { toDeleteIDs.contains($0.id) }
                                ruleStore.saveRules()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bộ Lọc Safari")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddRuleSheet = true }) {
                        Label("Thêm quy tắc", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showAddRuleSheet) {
                NavigationView {
                    Form {
                        Section(header: Text("Thông tin quy tắc mới")) {
                            TextField("Tên gợi nhớ (VD: Banner trang phim)", text: $newRuleName)
                            TextField("Tên miền hoặc CSS Selector (VD: #float_ck, .banner-qc)", text: $newRuleDomain)
                                .autocapitalization(.none)
                            Picker("Phân loại", selection: $newRuleCategory) {
                                ForEach(RuleCategory.allCases, id: \.self) { cat in
                                    Text(cat.rawValue).tag(cat)
                                }
                            }
                        }
                    }
                    .navigationTitle("Thêm Quy Tắc Chặn")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Hủy") { showAddRuleSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Lưu") {
                                ruleStore.addCustomRule(
                                    name: newRuleName,
                                    domainOrSelector: newRuleDomain,
                                    category: newRuleCategory
                                )
                                newRuleName = ""
                                newRuleDomain = ""
                                showAddRuleSheet = false
                                ruleStore.reloadSafariContentBlocker()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tab 4: DNS Config for All Apps
    private var dnsConfigTab: some View {
        NavigationView {
            Form {
                Section(header: Text("Máy Chủ Lọc Quảng Cáo Toàn Hệ Thống (DoH)")) {
                    ForEach(adBlockManager.providers) { provider in
                        Button(action: {
                            adBlockManager.selectedProvider = provider
                        }) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: adBlockManager.selectedProvider.id == provider.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(adBlockManager.selectedProvider.id == provider.id ? .green : .secondary)
                                    .font(.title3)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(provider.name)
                                            .font(.subheadline.bold())
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Text(provider.badge)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.2))
                                            .foregroundColor(.green)
                                            .cornerRadius(6)
                                    }
                                    Text(provider.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(provider.dohURL)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.mint)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if adBlockManager.selectedProvider.id == "custom_doh" {
                    Section(header: Text("Link DNS-over-HTTPS Cá Nhân")) {
                        TextField("https://dns.nextdns.io/your-id", text: $adBlockManager.customDoHURL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                    }
                }

                Section(
                    header: Text("Loại trừ mạng Wi-Fi (Tùy chọn)"),
                    footer: Text("Nhập tên mạng Wi-Fi (cách nhau bởi dấu phẩy) nếu bạn muốn tự động tắt DNS khi kết nối vào mạng nội bộ.")
                ) {
                    TextField("Ví dụ: Office_WiFi, Home_LAN", text: $adBlockManager.excludedWiFiSSIDs)
                }

                Section {
                    Button(action: {
                        adBlockManager.applySystemWideAdBlockDNS()
                    }) {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.shield.fill")
                            Text("Áp Dụng Cấu Hình DNS Này")
                                .fontWeight(.bold)
                            Spacer()
                        }
                    }
                    .foregroundColor(.green)
                }
            }
            .navigationTitle("Chặn Quảng Cáo App")
        }
    }

    // MARK: - Tab 5: Setup Guide
    private var guideTab: some View {
        NavigationView {
            List {
                Section(header: Text("1. Bật cả 2 Phần Mở Rộng trong Safari")) {
                    Label("Vào Cài đặt (Settings) > Safari > Phần mở rộng (Extensions).", systemImage: "1.circle.fill")
                    Label("Bật 'AdShield Safari Blocker' (chặn 220+ mạng quảng cáo, nhà cái & ẩn banner).", systemImage: "2.circle.fill")
                    Label("Bật 'AdShield Web Guard' và chọn 'Cho phép' trên mọi trang web để dùng tính năng: Khóa Mở Liên Kết & Nhấn Giữ 0.6s Vào Panel Để Chặn.", systemImage: "3.circle.fill")
                }

                Section(header: Text("2. Cách dùng tính năng Nhấn Giữ Chặn Panel & Khóa Link")) {
                    Label("Trên Safari: Khi đã bật AdShield Web Guard, ở góc dưới bên phải trang web sẽ có nút '🛡️ AdShield'. Bấm vào nút đó để bật '🔒 Đang Khóa Mọi Link' (bấm vào bất kỳ liên kết nào cũng không mở sang trang khác).", systemImage: "lock.fill")
                    Label("Nhấn giữ xóa khung: Nhấn giữ ngón tay khoảng 0.6 giây vào bất kỳ banner/panel quảng cáo nào trên trang web -> Hộp thoại hiện ra -> bấm 'Chặn Ngay' (hoặc 'Khung Lớn Hơn') để xóa vĩnh viễn khung đó.", systemImage: "hand.tap.fill")
                    Label("Bạn cũng có thể mở tab 'Nhấn Giữ Chặn' ngay trong ứng dụng AdShield Pro để duyệt web, khóa liên kết và nhấn giữ chặn bất kỳ khung nào rồi đồng bộ thẳng sang Safari.", systemImage: "globe")
                }
            }
            .navigationTitle("Hướng Dẫn")
        }
    }

    private func exportMobileConfigFile() {
        let xmlContent = adBlockManager.generateMobileConfigXML()
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("AdShieldPro-DNS.mobileconfig")
        do {
            try xmlContent.write(to: fileURL, atomically: true, encoding: .utf8)
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController else { return }
            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            rootVC.present(activityVC, animated: true)
        } catch {
            adBlockManager.statusMessage = "Không thể xuất file cấu hình: \(error.localizedDescription)"
        }
    }
}
