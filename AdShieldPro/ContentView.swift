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
    @State private var showExportAlert: Bool = false
    @State private var exportedProfileURL: URL?

    var body: some View {
        TabView(selection: $selectedTab) {
            dashboardTab
                .tabItem {
                    Label("Bảo Vệ", systemImage: "shield.lefthalf.filled")
                }
                .tag(0)

            dnsConfigTab
                .tabItem {
                    Label("Chặn App (DNS)", systemImage: "network.badge.shield.half.filled")
                }
                .tag(1)

            safariRulesTab
                .tabItem {
                    Label("Chặn Safari", systemImage: "safari.fill")
                }
                .tag(2)

            guideTab
                .tabItem {
                    Label("Hướng Dẫn", systemImage: "book.closed.fill")
                }
                .tag(3)
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
                VStack(spacing: 20) {
                    // Hero Shield Card
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(
                                    adBlockManager.isSystemDNSActive
                                    ? Color.green.opacity(0.18)
                                    : Color.orange.opacity(0.15)
                                )
                                .frame(width: 110, height: 110)

                            Image(systemName: adBlockManager.isSystemDNSActive ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .font(.system(size: 54))
                                .foregroundColor(adBlockManager.isSystemDNSActive ? .green : .orange)
                        }

                        Text(adBlockManager.isSystemDNSActive ? "Đang Bảo Vệ Toàn Hệ Thống" : "Chưa Bật Chặn Toàn Hệ Thống")
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
                    .padding(20)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(18)

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
                            value: "\(ruleStore.rules.filter(\.isEnabled).count) quy tắc",
                            subtitle: adBlockManager.isSafariBlockerEnabled ? "Đã kích hoạt" : "Kiểm tra Cài đặt",
                            icon: "safari.fill",
                            color: adBlockManager.isSafariBlockerEnabled ? .blue : .orange
                        )
                    }

                    // Quick Profile Fallback Card (Very helpful for unsigned/sideloaded IPA users)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "doc.badge.gearshape.fill")
                                .foregroundColor(.mint)
                            Text("Chế độ Sideload / Chứng chỉ Free (AltStore, TrollStore, ESign)")
                                .font(.subheadline.bold())
                        }
                        Text("Nếu chứng chỉ ký IPA của bạn không có quyền Network Extension trả phí của Apple, bạn có thể xuất trực tiếp file cấu hình DNS (.mobileconfig) để cài vào Cài đặt iPhone chỉ với 1 chạm.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button(action: exportMobileConfigFile) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Xuất Cấu Hình DNS (.mobileconfig)")
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

    // MARK: - Tab 2: DNS Config for All Apps
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
                    footer: Text("Nhập tên mạng Wi-Fi (cách nhau bởi dấu phẩy) nếu bạn muốn tự động tắt DNS khi kết nối vào mạng nội bộ công ty.")
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

    // MARK: - Tab 3: Safari Content Blocker Rules
    private var safariRulesTab: some View {
        NavigationView {
            List {
                Section {
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

                ForEach(RuleCategory.allCases, id: \.self) { category in
                    let categoryRules = ruleStore.rules.filter { $0.category == category }
                    if !categoryRules.isEmpty {
                        Section(header: Text(category.rawValue)) {
                            ForEach(categoryRules) { rule in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(rule.name)
                                            .font(.subheadline.weight(.medium))
                                        Text(rule.domainOrSelector)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundColor(.secondary)
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
                        Label("Thêm miền", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showAddRuleSheet) {
                NavigationView {
                    Form {
                        Section(header: Text("Thông tin quy tắc mới")) {
                            TextField("Tên gợi nhớ (VD: Quảng cáo báo chí)", text: $newRuleName)
                            TextField("Tên miền hoặc CSS Selector (VD: ads.example.com)", text: $newRuleDomain)
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

    // MARK: - Tab 4: Setup Guide
    private var guideTab: some View {
        NavigationView {
            List {
                Section(header: Text("1. Kích hoạt chặn quảng cáo trên các App khác")) {
                    Label("Bước 1: Mở tab 'Chặn App (DNS)', chọn AdGuard DNS hoặc Control D rồi bấm 'Áp Dụng Cấu Hình DNS'.", systemImage: "1.circle.fill")
                    Label("Bước 2: Mở ứng dụng Cài đặt (Settings) trên iPhone > Cài đặt chung (General) > Quản lý VPN & Thiết bị (VPN & Device Management) > mục DNS > chọn 'AdShield Pro'.", systemImage: "2.circle.fill")
                    Label("Lưu ý Sideload: Nếu bạn cài file IPA qua TrollStore / ESign / AltStore với chứng chỉ cá nhân không có quyền Network Extension, hãy bấm nút 'Xuất Cấu Hình DNS (.mobileconfig)' ở trang chủ để cài đặt trực tiếp vào máy.", systemImage: "info.circle.fill")
                }

                Section(header: Text("2. Kích hoạt chặn quảng cáo trên Safari")) {
                    Label("Bước 1: Mở Cài đặt (Settings) trên iPhone > chọn Safari > Phần mở rộng (Extensions).", systemImage: "1.circle.fill")
                    Label("Bước 2: Bật công tắc 'AdShield Safari Blocker' và cấp quyền cho phép trên mọi trang web.", systemImage: "2.circle.fill")
                    Label("Bước 3: Quay lại ứng dụng AdShield Pro > tab 'Chặn Safari' > bấm 'Cập nhật' để nạp danh sách quy tắc mới nhất.", systemImage: "3.circle.fill")
                }

                Section(header: Text("3. Phạm vi hoạt động")) {
                    Text("• Chặn quảng cáo banner, pop-up và video xen kẽ trong các ứng dụng đọc báo, tiện ích, game mobile thông qua bộ lọc DNS mã hóa (DoH).\n• Chặn quảng cáo hiển thị, ẩn khung banner rỗng và chặn script theo dõi trên trình duyệt Safari nhờ WebKit Content Blocker.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Hướng Dẫn Cài Đặt")
        }
    }

    // MARK: - Export .mobileconfig Helper
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
