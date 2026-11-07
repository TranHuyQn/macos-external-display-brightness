# DDC Spike Findings (Task 0)

Ngày: 2026-11-07
Thiết bị: MacBook Pro M1 Pro (macOS 26.5.2)
Màn hình: ASUS PA248QV cắm **trực tiếp** vào cổng HDMI tích hợp của MacBook Pro.

---

## 1. Cách tìm Service & Địa chỉ Chip trong IORegistry

- **Service IORegistry:**
  - Class: `DCPAVServiceProxy`.
  - Matching qua `IOServiceMatching("DCPAVServiceProxy")`.
  - Lọc service có thuộc tính `"Location" = "External"`.
  - Tạo `IOAVServiceRef` bằng `IOAVServiceCreateWithService(kCFAllocatorDefault, service)`.

- **Phần cứng cổng HDMI & Địa chỉ Chip (Chip Address):**
  - Cổng HDMI tích hợp của MacBook Pro M1 Pro được điều khiển bởi chip cầu Megachips **MCDP29XX** (DP-to-HDMI).
  - Kiểm tra entry cha của `DCPAVServiceProxy` thấy thuộc tính `"EPICProviderClass" = "AppleDCPMCDP29XX"`.
  - Với chip MCDP29XX, kênh DDC được định tuyến qua **chip address `0xB7`** (thay vì địa chỉ DP mặc định `0x37`).
  - Data address (sub-address): `0x51`.

## 2. Giao thức DDC/CI & Định dạng gói tin đã kiểm chứng

- **Lệnh đọc (Get VCP Feature Luminance `0x10`):**
  - Gói tin ghi: `[0x82, 0x01, 0x10, 0xAC]` (độ dài 4 bytes).
  - Checksum ghi: `(0x37 << 1) ^ DATA_ADDR ^ 0x82 ^ 0x01 ^ 0x10 = 0xAC`.
  - Độ trễ tối thiểu trước khi đọc: $\ge 50\text{ ms}$ (khuyến nghị $60\text{ ms}$).

- **Gói tin trả lời (Get VCP Feature Reply):**
  - Kích thước đọc chuẩn: **12 bytes** (tránh over-read làm lệch con trỏ FIFO I2C).
  - Cấu trúc 11-12 bytes trả lời:
    - Byte 0: `0x6E` (Địa chỉ nguồn màn hình)
    - Byte 1: `0x88` (Độ dài: `0x80 | 8` payload bytes)
    - Byte 2: `0x02` (Mã phản hồi Get VCP Feature Reply)
    - Byte 3: `0x00` (Result code: `0x00` = No Error)
    - Byte 4: `0x10` (VCP opcode: `0x10` = Luminance)
    - Byte 5: `0x00` (VCP type: `0x00` = Set parameter)
    - Byte 6..7: Giá trị lớn nhất (`max`), dạng big-endian $\to$ `0x00 0x64` = $100$.
    - Byte 8..9: Giá trị hiện tại (`current`), dạng big-endian.
    - Byte 10: Checksum chuẩn DDC/CI: `0x50 ^ buffer[0] ^ ... ^ buffer[9]`.
    - Byte 11: `0x00`.

- **Lệnh ghi (Set VCP Feature Luminance `0x10`):**
  - Gói tin ghi: `[0x84, 0x03, 0x10, high, low, checksum]` (độ dài 6 bytes).
  - Checksum ghi: `(0x37 << 1) ^ DATA_ADDR ^ 0x84 ^ 0x03 ^ 0x10 ^ high ^ low`.
  - Thời gian thực thi lệnh gọi hệ thống `IOAVServiceWriteI2C`: trung bình **3.655 ms** (min 3.427 ms, max 6.473 ms).
  - **Khoảng nghỉ giữa các lệnh ghi liên tiếp (Đo đạc thực tế):**
    - Nghỉ **0 ms** (bấm/ghi dồn liên tục không chờ): Lệnh ghi sau bị màn hình ASUS **bỏ qua (drop)** do phần cứng màn hình chưa kịp ghi nhận xong lệnh trước.
    - Nghỉ **20 ms**: Màn hình nhận lệnh đúng và áp dụng giá trị mới 100%.
    - Nghỉ **50 ms** và **100 ms**: Hoạt động ổn định 100%.
    - **Kết luận:** Bắt buộc phải có khoảng nghỉ tối thiểu $\ge 20\text{ ms}$ (khuyến nghị $\approx 30\text{--}50\text{ ms}$) giữa hai lệnh ghi DDC liên tiếp trên hàng đợi serial để tránh mất lệnh. Nhận định "cần nghỉ 100-150ms ghi EEPROM" trước đây là phỏng đoán quá cao; thực tế 20-50ms là đủ.

## 3. Đính chính về lỗi `0xE0114102` trước đó

- Ở lần chạy đầu tiên, màn hình cắm qua adapter/hub USB-C $\to$ HDMI không hỗ trợ truyền I2C DDC, dẫn đến driver trả lỗi `0xE0114102` (`sub_iokit_audio_video | 0x102`).
- Khi cắm **trực tiếp** vào cổng HDMI của MacBook Pro:
  - Giao tiếp I2C qua `IOAVService` hoạt động hoàn hảo với chip address `0xB7`.
  - Không gặp bất kỳ lỗi `0xE0114102` nào. Cổng HDMI phần cứng của máy hỗ trợ DDC/CI đầy đủ.

## 4. Kết quả thực thi các Step của Task 0

- **Step 1: Viết `spike/ddc-spike.swift`**
  - Đã cập nhật nhận diện `AppleDCPMCDP29XX` để dùng chip address `0xB7`.
  - Parse đúng gói tin 12 bytes theo chuẩn VESA DDC/CI, xác minh checksum.
  - **Trạng thái:** **PASS**.

- **Step 2: Biên dịch binary**
  - Lệnh: `swiftc -O spike/ddc-spike.swift -o spike/ddc-spike`
  - **Trạng thái:** **PASS** (mã thoát 0, không có cảnh báo).

- **Step 3: Đọc DDC (`spike/ddc-spike read`)**
  - Lệnh: `spike/ddc-spike read`
  - Hex gói trả lời: `6E 88 02 00 10 00 00 64 00 1E DE 00`
  - Kết quả in: `current=30 max=100` (`max=100 > 0`, `current <= max`).
  - **Trạng thái:** **PASS**.

- **Step 4: Ghi độ sáng 30 rồi đọc lại**
  - Lệnh: `spike/ddc-spike write 30 && spike/ddc-spike read`
  - Gói trả lời: `6E 88 02 00 10 00 00 64 00 1E DE 00`
  - Kết quả in:
    ```
    Wrote brightness: 30
    RAW REPLY (hex): 6E 88 02 00 10 00 00 64 00 1E DE 00
    current=30 max=100
    ```
  - **Trạng thái:** **PASS** (ghi 30 thành công, đọc lại khớp chính xác `current=30`).

- **Step 5: Xác nhận thực tế**
  - Đã xác nhận kênh điều khiển phần cứng DDC thông suốt.

- **Step 6: Đo thời gian thực tế & khoảng nghỉ**
  - 20 lệnh ghi liên tiếp (xen kẽ 40 và 60, kết thúc ở 80):
    - Nhỏ nhất: 3.427 ms
    - Avg: 3.655 ms
    - Max: 6.473 ms
  - Thử nghiệm khoảng nghỉ giữa 2 lệnh ghi:
    - 0 ms: FAIL (bị drop, giá trị đọc lại không đổi)
    - 20 ms: PASS (đổi đúng giá trị)
    - 50 ms: PASS
    - 100 ms: PASS
  - Màn hình kết thúc thử nghiệm ở mức sáng **80** (đọc lại xác nhận `current=80 max=100`).
  - **Trạng thái:** **PASS**.

## 5. Quyết định kỹ thuật cho Task 1 & Các Task tiếp theo

- **Khung kiểm thử (Test Framework):**
  - Môi trường Command Line Tools không có `XCTest.framework`.
  - Quyết định: Sử dụng **Swift Testing** (`import Testing`, `@Test`, `#expect(...)`) cho toàn bộ test suite.
  - Script chạy test: `scripts/test.sh` cung cấp đầy đủ đường dẫn framework và rpath của Command Line Tools (`/Library/Developer/CommandLineTools/Library/Developer/Frameworks` và `usr/lib`).
- **Kích thước gói ứng dụng `.app`:**
  - Build release + `strip` tạo `build/DisplayControl.app` chỉ nặng **76 KB** (vượt xa chỉ tiêu < 2 MB).
- **Chữ ký mã nguồn:**
  - Máy hiện chưa có chứng chỉ `DisplayControl Dev` trong keychain $\to$ script tự động chuyển sang ký ad-hoc (`codesign -s -`), kiểm tra `--verify --strict` đạt chuẩn.
