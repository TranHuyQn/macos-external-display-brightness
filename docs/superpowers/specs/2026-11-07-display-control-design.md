# Display Control — Tài liệu thiết kế

Ngày: 2026-11-07 · Chủ dự án: Huy · Trạng thái: đã duyệt ý tưởng, chờ kế hoạch triển khai

## 1. Mục đích

Huy dùng MacBook Pro M1 Pro (macOS 26.5.2) với một màn rời ASUS PA248QV cắm qua HDMI.
Huy đã gỡ BetterDisplay vì (1) trả phí, muốn có app miễn phí của riêng mình và có thể
open source sau này, (2) chỉ cần đúng một chức năng: chỉnh độ sáng màn rời.

Mục tiêu: một app native nhỏ trên menu bar, chỉnh **độ sáng phần cứng thật** của màn rời
bằng phím F1/F2 như cách macOS chỉnh màn MacBook.

## 2. Mục tiêu

1. Bấm phím độ sáng (F1 giảm, F2 tăng) thì chỉnh độ sáng màn rời.
2. Màn nào đang chứa con trỏ chuột thì chỉnh màn đó.
3. Chỉnh qua DDC/CI (VCP 0x10), tức độ sáng thật của màn, không phải overlay/gamma.
4. Native, nhẹ nhất: dung lượng nhỏ, CPU và RAM tối thiểu.

## 3. Không làm (non-goals)

- Chỉnh màu, độ tương phản, âm lượng, độ phân giải, input source.
- Hỗ trợ nhiều màn rời cùng lúc (chỉ 1 màn rời, cổng HDMI). Thiết kế không được chặn việc mở rộng sau này.
- Chỉnh màn MacBook: khi chuột ở màn trong, app **không can thiệp**, macOS tự xử lý.
- Phát hành cho người khác, notarize, tài khoản Apple Developer.
- Chế độ fallback bằng gamma/overlay khi DDC không chạy.

## 4. Anti-goals (coi là thất bại dù chạy được)

- App ngốn tài nguyên khi rảnh (timer chạy nền, polling, CPU khác 0%).
- Bấm F1/F2 làm mất phím cho màn MacBook khi chuột ở màn trong.
- Làm treo giao diện hoặc phím bấm vì DDC chậm.
- Kéo thêm thư viện ngoài hoặc framework nặng (SwiftUI, Electron, Python runtime...).

## 5. Ràng buộc và quyết định đã chốt

Do Huy chốt:
- Chuột ở màn MacBook thì để macOS tự xử lý.
- Giao diện: icon menu bar và thanh độ sáng (OSD) hiện khi bấm phím.
- Một màn rời, HDMI. Dùng cá nhân trên máy này, ký ad-hoc/self-signed.
- Màn rời phải **cắm trực tiếp vào cổng HDMI của MacBook, không qua hub/dock**. Qua hub thì ghi DDC báo lỗi `0xE0114102` (đã kiểm chứng 2026-11-07); cắm trực tiếp thì đọc DDC được.
- Bước đầu tiên của kế hoạch là thử nghiệm xác nhận DDC chạy trên cổng HDMI này.

Do Min đề xuất (Huy đã duyệt tổng thể):
- Swift + AppKit, không SwiftUI, không thư viện ngoài. Build bằng Swift Package Manager với Command Line Tools (máy chưa có Xcode đầy đủ); tự đóng gói `.app` bằng script.
- Bắt phím: event tap trên sự kiện phím hệ thống (`NX_SYSDEFINED`, subtype 8, keycode `NX_KEYTYPE_BRIGHTNESS_UP=2`, `DOWN=3`). Cần quyền Accessibility.
- DDC: API riêng tư `IOAVService` (`IOAVServiceCreateWithService`, `IOAVServiceWriteI2C`, `IOAVServiceReadI2C`), chip addr `0x37` (mặc định) hoặc `0xB7` (cổng HDMI MacBook qua cầu MCDP29XX, nhận biết bằng `EPICProviderClass = AppleDCPMCDP29XX`; đã kiểm chứng trên máy này), data addr `0x51`, VCP `0x10`. Đây là cách duy nhất chạy trên Apple Silicon; rủi ro là Apple có thể đổi API trong bản macOS sau.
- 16 nấc như macOS, ánh xạ vào dải DDC 0..max (đọc `max` từ màn, thường 100).
- Nhớ độ sáng lần cuối (UserDefaults); khi khởi động đọc lại giá trị thật từ màn.
- Tự khởi động cùng máy (`SMAppService`), tắt/bật được trong menu.
- Menu: hiển thị tên màn rời + mức sáng hiện tại, bật/tắt khởi động cùng máy, bật/tắt icon, Thoát.

Do Huy bổ sung (2026-11-07):
- Có công tắc **ẩn/hiện icon menu bar**. Khi ẩn, F1/F2 và OSD vẫn hoạt động bình thường, app vẫn chạy nền.
- Huy không cần icon. Muốn chỉnh gì thì **mở lại app** (Spotlight/Finder).

Do Min đoán (cần Huy xác nhận): mở lại app khi nó đang chạy sẽ hiện một **cửa sổ cài đặt nhỏ**
chứa: công tắc hiện icon, công tắc khởi động cùng máy, nút Thoát. Cửa sổ chỉ tạo khi cần và
giải phóng khi đóng (không giữ RAM lúc rảnh). Công tắc icon cũng có trong menu bar khi icon đang hiện.

## 6. Hành vi chi tiết

**Xác định màn đích.** Khi nhận phím: lấy vị trí chuột, tìm `NSScreen` chứa nó, lấy
`CGDirectDisplayID`. Nếu `CGDisplayIsBuiltin` là true thì cho sự kiện đi tiếp (không nuốt).
Nếu là màn rời thì nuốt sự kiện và xử lý.

**Ánh xạ màn ↔ IOAVService.** Ghép `CGDirectDisplayID` với service DDC qua EDID
(vendor/product/serial) hoặc đường dẫn IORegistry; chọn service có location `External`.
Cache kết quả, chỉ dò lại khi có thông báo đổi cấu hình màn hình
(`didChangeScreenParametersNotification`), không polling.

**Ghi DDC.** DDC chậm (khoảng 30–100 ms mỗi lệnh). Mọi lệnh chạy trên một hàng đợi nền
serial; áp dụng "giá trị mới nhất thắng" (bỏ qua giá trị trung gian khi bấm giữ). Luồng
phím không bao giờ chờ DDC. Có retry ngắn khi ghi lỗi.

**OSD.** Panel không viền, `ignoresMouseEvents`, nổi trên mọi cửa sổ, hiện ở màn đang chứa
chuột, tự ẩn sau khoảng 1,5 giây. Tạo lười (lần đầu cần dùng), vẽ bằng Core Graphics/CALayer,
không ảnh động tốn tài nguyên.

**Ẩn/hiện icon.** Trạng thái lưu trong UserDefaults, mặc định là hiện. Ẩn icon chỉ gỡ
`NSStatusItem`, không dừng event tap hay DDC. App chạy dạng agent (không icon Dock). Khi nhận
sự kiện mở lại app (`applicationShouldHandleReopen`) thì hiện cửa sổ cài đặt. Lần chạy đầu tiên
luôn hiện icon để người dùng thấy app đã chạy.

**Mất kết nối / ngủ.** Khi màn rời rút ra hoặc máy ngủ/thức, app không crash; bấm phím
khi chưa có màn đích thì không làm gì. Sau khi thức hoặc cắm lại, dò lại màn và đồng bộ độ sáng.

**Quyền.** Chưa có quyền Accessibility thì menu báo rõ và hướng dẫn mở đúng mục trong
System Settings; app không crash. Lưu ý: ký ad-hoc khiến chữ ký đổi mỗi lần build và macOS
có thể thu hồi quyền; dùng một chứng chỉ self-signed cố định để giữ quyền giữa các lần build.

## 7. Chỉ tiêu nhẹ (kiểm chứng được)

- CPU khi rảnh: 0,0% (không timer, không polling).
- RAM khi rảnh: mục tiêu dưới 25 MB tính theo physical footprint (`footprint -p`); RSS gồm thư viện hệ thống dùng chung nên không dùng làm chỉ tiêu. Đã đo bản hiện tại: 12 MB.
- Dung lượng `.app`: mục tiêu dưới 2 MB (build `-Osize`, strip).
- Từ lúc bấm phím đến lúc OSD hiện: dưới 50 ms; đến lúc màn đổi sáng: dưới 300 ms.

## 8. Tiêu chí thành công

1. Chuột ở màn PA248QV, bấm F1/F2: độ sáng màn đổi theo từng nấc, OSD hiện đúng mức.
2. Chuột ở màn MacBook, bấm F1/F2: màn MacBook đổi như bình thường, màn rời không đổi.
3. Độ sáng đổi là độ sáng thật của màn (nhìn menu OSD của chính màn khớp), không phải phủ tối.
4. Giữ phím không gây treo, không tạo hàng đợi lệnh dồn.
5. Đạt các chỉ tiêu ở mục 7.
6. Khởi động lại máy: app tự chạy, vẫn hoạt động sau khi đã cấp quyền một lần.
7. Ẩn icon: icon biến mất khỏi menu bar, F1/F2 và OSD vẫn chạy; mở lại app thì hiện cửa sổ cài đặt, bật lại icon được. Tắt/mở máy vẫn giữ trạng thái ẩn.

## 9. Rủi ro đã biết

| Rủi ro | Ảnh hưởng | Cách xử lý |
|---|---|---|
| DDC qua HDMI không chạy trên máy này | Cả hướng đi phải đổi | Bước 1 là thử nghiệm riêng, pass mới đi tiếp |
| `IOAVService` là API riêng tư, có thể đổi | App hỏng sau bản macOS mới | Cô lập vào một module nhỏ, ghi chú phiên bản macOS đã kiểm chứng |
| Event tap bị tắt do timeout hoặc mất quyền | Phím ngừng hoạt động im lặng | Lắng nghe `tapDisabledByTimeout`, bật lại tap; kiểm tra quyền khi khởi động |
| Ký ad-hoc làm mất quyền Accessibility giữa các build | Phải cấp quyền lại | Dùng chứng chỉ self-signed cố định |
| `SMAppService` với app ký không chính thức | Khởi động cùng máy có thể không đăng ký được | Kiểm chứng sớm; phương án dự phòng là LaunchAgent plist |

## 10. Giao cho người xây dựng tự quyết

Cấu trúc module, cách ghép màn với IOAVService (EDID hay đường dẫn IORegistry), kích thước và
kiểu vẽ OSD, tên bundle identifier, cách đóng gói `.app` bằng script, cách viết test cho
phần logic thuần (ánh xạ nấc, throttle).
