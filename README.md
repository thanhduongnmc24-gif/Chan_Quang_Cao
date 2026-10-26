# AdShield Pro (iOS) — Chặn Quảng Cáo Mọi Ứng Dụng (DNS) & Safari

Dự án ứng dụng iOS viết bằng **SwiftUI** được thiết kế tối ưu cho quy trình làm việc trên **VS Code + GitHub Actions**: không cần máy Mac cá nhân, chỉ cần `git push` lên GitHub là Action tự động sinh `AdShieldPro.xcodeproj` bằng **XcodeGen**, biên dịch bản `Release` không ký (`CODE_SIGNING_ALLOWED=NO`) và đóng gói thành **`AdShieldPro-Unsigned.ipa`** để bạn tải về cài qua **TrollStore, ESign, Feather, Sideloadly hoặc AltStore**.

---

## Tính năng chính

1. **Chặn quảng cáo trên tất cả các ứng dụng khác (System-Wide Encrypted DNS - DoH)**:
   - Tích hợp `NEDNSSettingsManager` (`NetworkExtension.framework`) để cấu hình **DNS-over-HTTPS (DoH)** ở cấp hệ điều hành iOS.
   - Tích hợp sẵn các máy chủ lọc quảng cáo mạnh nhất: **AdGuard DNS**, **AdGuard Family**, **Mullvad AdBlock DNS**, **Control D**, và hỗ trợ nhập link **NextDNS / AdGuard Private** cá nhân.
   - Hỗ trợ danh sách mạng Wi-Fi loại trừ (`OnDemandRules` SSID).
   - **Cơ chế dự phòng cho máy Sideload chứng chỉ miễn phí**: Có nút **Xuất Cấu Hình DNS (`.mobileconfig`)** ngay trong app để cài trực tiếp vào iPhone nếu chứng chỉ ký IPA của bạn không có entitlement `com.apple.developer.networking.networkextension`.

2. **Chặn quảng cáo & ẩn khung banner trên Safari (`SafariBlocker` App Extension)**:
   - Sử dụng `SFContentBlockerManager` (`SafariServices.framework`) kết hợp App Group (`group.com.adshield.pro`).
   - Cho phép bật/tắt từng quy tắc chặn mạng quảng cáo (`doubleclick.net`, `googlesyndication.com`, `applovin.com`, `unityads`, `taboola`, `popads`...), trình theo dõi (`appsflyer`, `adjust`, `google-analytics`, `facebook pixel`) và quy tắc CSS (`css-display-none`) để xóa khoảng trắng quảng cáo trên báo điện tử.
   - Cho phép người dùng tự thêm tên miền hoặc CSS Selector mới ngay trên giao diện iPhone.

---

## Cấu trúc thư mục (Tối ưu cho VS Code)

```text
AdShieldPro/
├── .github/
│   └── workflows/
│       └── build-ipa.yml              # GitHub Actions tự động build ra file .ipa chưa ký
├── project.yml                        # Cấu hình XcodeGen (tự tạo file .xcodeproj trên CI)
├── AdShieldPro/                       # Target ứng dụng chính (iOS 15.0+)
│   ├── AdShieldApp.swift              # Entry point (@main)
│   ├── ContentView.swift              # Giao diện 4 tab: Bảo Vệ, Chặn App (DNS), Chặn Safari, Hướng Dẫn
│   ├── AdBlockManager.swift           # Quản lý NEDNSSettingsManager (DoH) & xuất .mobileconfig
│   ├── BlockerRuleStore.swift         # Quản lý quy tắc Safari Content Blocker & đồng bộ App Group
│   ├── Info.plist                     # Cấu hình Bundle App chính
│   ├── AdShieldPro.entitlements       # Quyền Network Extension (dns-settings) & App Groups
│   └── Resources/Assets.xcassets/     # Bộ icon và màu chủ đạo (AccentColor)
├── SafariBlocker/                     # Target Safari Content Blocker Extension (.appex)
│   ├── ContentBlockerRequestHandler.swift
│   ├── blockerList.json               # Danh sách quy tắc WebKit Content Blocker mặc định
│   ├── Info.plist                     # Khai báo NSExtensionPointIdentifier com.apple.Safari.content-blocker
│   └── SafariBlocker.entitlements     # Quyền App Group chia sẻ dữ liệu với app chính
└── scripts/
    └── package_ipa.sh                 # Script chạy local (nếu build trên máy Mac)
```

---

## Hướng dẫn đưa lên GitHub bằng VS Code để lấy file `.ipa`

### Bước 1: Mở thư mục dự án trong VS Code và đẩy lên GitHub
Mở Terminal trong VS Code tại thư mục giải nén `AdShieldPro` và chạy:

```bash
git init
git add .
git commit -m "Initial commit: AdShield Pro iOS DNS + Safari AdBlocker"
git branch -M main
git remote add origin https://github.com/<TEN_GITHUB_CUA_BAN>/<TEN_REPO>.git
git push -u origin main
```

### Bước 2: Tải file `AdShieldPro-Unsigned.ipa` từ GitHub Actions
1. Truy cập kho lưu trữ (Repository) của bạn trên GitHub, mở tab **Actions**.
2. Chọn workflow **Build Unsigned iOS IPA** (tự động chạy ngay sau khi bạn push hoặc bạn có thể bấm **Run workflow**).
3. Đợi khoảng 2–3 phút để máy ảo `macos-14` tạo project từ `project.yml`, biên dịch cả 2 target (`AdShieldPro` và `SafariBlocker.appex`), gắn fake-sign `ldid` và đóng gói.
4. Cuộn xuống mục **Artifacts** ở cuối trang chạy Action và tải **`AdShieldPro-Unsigned-IPA`** (bên trong có file `AdShieldPro-Unsigned.ipa`).

---

## Hướng dẫn cài đặt và kích hoạt trên iPhone

1. **Cài đặt IPA**:
   - **TrollStore**: Mở file `AdShieldPro-Unsigned.ipa` trực tiếp qua TrollStore (giữ nguyên toàn bộ quyền `dns-settings` và `App Groups` nhờ bước `ldid` trong Action).
   - **ESign / Feather / Sideloadly / AltStore**: Ký bằng chứng chỉ của bạn và cài đặt như bình thường.
2. **Bật chặn quảng cáo các App khác (DNS)**:
   - Mở **AdShield Pro** -> chọn máy chủ **AdGuard DNS** -> bấm **Bật Chặn Mọi App (DNS)**.
   - Vào **Cài đặt (Settings) > Cài đặt chung (General) > Quản lý VPN & Thiết bị (VPN & Device Management) > DNS** -> chọn **AdShield Pro**.
   - *(Nếu chứng chỉ ký của bạn không hỗ trợ Network Extension, bấm nút **"Xuất Cấu Hình DNS (.mobileconfig)"** ngay tại màn hình chính của app để cài profile DoH vào máy).*
3. **Bật chặn quảng cáo trên Safari**:
   - Vào **Cài đặt (Settings) > Safari > Phần mở rộng (Extensions)** -> bật **AdShield Safari Blocker**.
