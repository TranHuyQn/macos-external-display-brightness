# DisplayControl: chỉnh độ sáng màn hình rời trên macOS (DDC/CI) bằng phím F1/F2

[English](README.md) · Tiếng Việt

Ứng dụng macOS bản địa nhẹ (native AppKit/Swift) chạy trên thanh Menu Bar dành riêng cho MacBook Pro M1 Pro (macOS 26.5.2), giúp điều khiển độ sáng phần cứng màn hình ngoài (ASUS PA248QV) qua giao thức DDC/CI (VCP `0x10`) khi nhấn các phím độ sáng F1/F2.

---

## Tính Năng Chính

- **Nhẹ & Tiết kiệm tài nguyên:** Viết hoàn toàn bằng Swift + AppKit bản địa (không SwiftUI, không Electron, không Python, không phụ thuộc thư viện ngoài). Kích thước `.app` chỉ ~450 KB, RAM physical footprint ~12 MB, CPU khi rảnh 0.0% (không dùng timer, không polling).
- **Điều khiển thông minh theo con trỏ chuột:**
  - Chuột ở màn hình ngoài: Nuốt phím F1/F2, điều chỉnh độ sáng màn ngoài qua DDC thật, hiển thị thanh OSD bản địa mượt mà.
  - Chuột ở màn hình tích hợp MacBook: Không can thiệp, phím F1/F2 hoạt động bình thường với màn hình MacBook và hiển thị OSD mặc định của macOS.
- **Dồn lệnh thông minh (Latest-Wins Writer):** Khi nhấn giữ hoặc bấm phím nhanh liên tục, cơ chế "mới nhất thắng" với khoảng cách an toàn 40 ms đảm bảo không làm nghẽn hàng đợi I2C của màn hình và tránh drop lệnh phần cứng.
- **Linh hoạt Menu Bar:** Cho phép ẩn icon Menu Bar để chạy ngầm hoàn toàn. Có thể mở lại ứng dụng bất kỳ lúc nào để hiển thị cửa sổ cài đặt.

---

## Yêu Cầu Phần Cứng & Kết Nối

> [!IMPORTANT]
> Màn hình ngoài phải được **cắm TRỰC TIẾP vào cổng HDMI tích hợp của MacBook Pro** (không cắm qua hub, dock hay cổng chuyển USB-C). Qua hub/dock, các dòng I2C DDC sẽ bị chặn dẫn đến lỗi phần cứng `0xE0114102`. Cổng HDMI trực tiếp của máy sử dụng chip cầu điều khiển Megachips MCDP29XX (chip address `0xB7`).

---

## Hướng Dẫn Sử Dụng

### 1. Biên dịch ứng dụng (`.app`)
Chạy script đóng gói, strip nhị phân và ký ad-hoc:
```bash
./scripts/build-app.sh
```
Sao chép mã nguồn: `git clone https://github.com/TranHuyQn/macos-external-display-brightness.git`.
File ứng dụng sẽ được tạo tại `build/DisplayControl.app`.

### 2. Chạy bộ kiểm thử tự động
Chạy toàn bộ test suite sử dụng Swift Testing:
```bash
./scripts/test.sh
```

### 3. Cấp quyền Accessibility (Chỉ cần làm một lần)
Vì ứng dụng cần lắng nghe và can thiệp sự kiện phím độ sáng (`NX_SYSDEFINED`), macOS yêu cầu quyền Accessibility:
1. Mở ứng dụng lần đầu:
   ```bash
   open build/DisplayControl.app
   ```
2. Vào **System Settings > Privacy & Security > Accessibility** (Cài đặt hệ thống > Quyền riêng tư & Bảo mật > Trợ năng).
3. Bật công tắc cấp quyền cho **DisplayControl**.

### 4. Cách mở lại cửa sổ cài đặt khi đã ẩn icon Menu Bar
Khi tuỳ chọn "Hiện icon trên Menu Bar" bị tắt, ứng dụng vẫn chạy ngầm dạng accessory (không có icon trên Dock). Để mở lại bảng cài đặt bật lại icon hoặc tuỳ chỉnh:
- Tìm và mở **DisplayControl** qua Spotlight / Finder, hoặc chạy lệnh:
  ```bash
  open build/DisplayControl.app
  ```
- Cửa sổ **Cài đặt DisplayControl** sẽ xuất hiện cho phép bật lại icon hoặc cấu hình "Khởi động cùng máy". Khi đóng cửa sổ, tài nguyên UI sẽ được giải phóng hoàn toàn để giữ RAM thấp.

---

## Giới Hạn Đã Biết

1. **API riêng tư `IOAVService`:** Kênh giao tiếp I2C DDC trên Apple Silicon sử dụng private framework `IOAVService` trong `DCPAVServiceProxy`. Apple có thể thay đổi cấu trúc này trong các bản cập nhật macOS tương lai. Toàn bộ giao tiếp đã được cô lập trong module `Sources/DisplayControl/DDC/AVServiceDDC.swift`.
2. **Môi trường kiểm chứng:** Ứng dụng đã được kiểm chứng hoạt động ổn định trên macOS 26.5.2 (Darwin 25.5.0, chip Apple Silicon M1 Pro).
3. **Cấu hình hỗ trợ:** Thiết kế chuyên biệt cho 1 màn hình ngoài kết nối qua HDMI.

---

## Giấy phép

[MIT](LICENSE) © 2026 TranHuyQn
