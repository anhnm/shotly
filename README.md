# Shotly

[![macOS](https://img.shields.io/badge/macOS-14.0+-black.svg)](https://github.com/anhnm/shotly/releases/latest)
[![Release](https://img.shields.io/github/v/release/anhnm/shotly)](https://github.com/anhnm/shotly/releases/latest)
[![License](https://img.shields.io/badge/license-BSD%203--Clause-green.svg)](LICENSE)
[![Website](https://img.shields.io/badge/web-shotly.anhnm.pro-42D396.svg)](https://shotly.anhnm.pro)

App chụp và quay màn hình cho macOS, viết bằng Swift: nhẹ, nhanh, chạy trên menu bar.
Chụp xong là chỉnh, chú thích, làm đẹp và chia sẻ ngay, với trình chỉnh sửa thao tác nhanh bằng phím.

## Tính năng

### Chụp và quay

| Thao tác | Phím tắt mặc định |
|---|---|
| Chụp vùng | `⌘⇧4` |
| Chụp toàn màn hình | `⌘⇧3` |
| Chụp cửa sổ | `⌘⇧6` |
| Quay màn hình | `⌘⇧2` |
| Nhận dạng chữ (OCR) | `⌘⇧O` |
| Lấy màu (hex) | `⌘⇧C` |

- Đóng băng màn hình bằng ScreenCaptureKit, sẵn sàng chọn vùng trong khoảng 30–50ms; giữ `Space` khi kéo để di chuyển vùng chọn.
- OCR có thể tự dịch kết quả (Apple Translation, macOS 15+).
- Quay màn hình ra MP4, có trình chỉnh video: cắt, crop, padding, bo góc, nền.
- Hẹn giờ chụp 3/5/10 giây. Đổi được mọi phím tắt trong Settings → Hotkeys.

### Thẻ xem nhanh sau khi chụp

Thẻ trong suốt hiện ngay cạnh con trỏ: bấm để mở editor, kéo thả thẳng vào app khác, hoặc dùng
các nút Edit `↩`, Copy `⌘C`, Save `⌘S`, Copy text (OCR) `T`, Pin `P`, Collage `G`. Tự ẩn khi
bấm ra ngoài; chụp nhiều ảnh liên tiếp thì ghép được thành collage.

### Trình chỉnh sửa

- Zoom và kéo ảnh: `Z` / `⇧Z` tại con trỏ, `⌘+` `⌘−`, `⌘1` vừa cửa sổ, `⌘0` kích thước thật, pinch, giữ `Space` để kéo.
- Màu dưới con trỏ hiện trên thanh công cụ: `Tab` copy mã màu, `⇧Tab` copy màu chữ gần đó.
- Đổi kích thước ảnh, crop, ghim ảnh lên màn hình.
- Chú thích: khung (bo góc / vuông / nét đứt / đặc), hình tròn, đường thẳng, mũi tên cong, vẽ tay,
  chữ, số thứ tự, thước đo, blur/mosaic, spotlight. Mỗi công cụ một phím: `V T M R D A B G N O L`.
- Backdrop: nền màu, gradient, hình nền macOS hoặc ảnh riêng; padding, bo góc, bóng đổ; watermark và metadata.

### Khác

- Lịch sử ảnh chụp và video, menu Recent trên menu bar.
- Tự kiểm tra và cài bản cập nhật từ GitHub Releases.
- Thống kê sử dụng ẩn danh, tắt được trong Settings → General → Privacy. Không bao giờ gửi ảnh, nội dung OCR, tên file hay dữ liệu cá nhân.

## Cài đặt

1. Tải `Shotly-<phiên bản>.dmg` mới nhất ở trang [Releases](https://github.com/anhnm/shotly/releases/latest).
2. Mở DMG, kéo Shotly vào Applications.
3. Lần đầu mở: chuột phải vào Shotly → **Open** (app chưa được Apple công chứng).
4. Cấp quyền **Screen Recording** (để chụp màn hình) và **Accessibility** (để thay phím tắt chụp mặc định của macOS).

Từ bản 2.0, Shotly tự cập nhật và giữ nguyên quyền qua các lần cập nhật.

## Build từ mã nguồn

Cần Xcode 16+ và [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/anhnm/shotly.git
cd shotly
make run
```

Project Xcode (`Shotly.xcodeproj`) được sinh từ `project.yml`; sau khi thêm hoặc đổi tên file, chạy `xcodegen generate`.

| Lệnh | Tác dụng |
|---|---|
| `make build` | Build Debug |
| `make run` | Build và mở app |
| `make release` | Build Release, ký bằng chứng chỉ "Shotly Self-Signed" nếu có (không thì ad-hoc) |
| `make dmg` | Đóng gói DMG để thử |
| `make lint` | Xem cảnh báo của trình biên dịch |
| `make clean` | Xoá file build |
| `make version` | In phiên bản hiện tại |

## Cấu trúc

Swift 6, SwiftUI kết hợp AppKit, không dùng thư viện ngoài.

| Thư mục | Nội dung |
|---|---|
| `Sources/App` | Khởi động app, quyền, phím tắt |
| `Sources/Capture` | Đóng băng màn hình, chọn vùng/cửa sổ, OCR, lấy màu |
| `Sources/Editor` | Trình chỉnh sửa: canvas, zoom, công cụ chú thích, thanh công cụ |
| `Sources/Preview` | Thẻ xem nhanh sau khi chụp, ghim ảnh |
| `Sources/Recording` | Quay màn hình và trình chỉnh video |
| `Sources/Settings` | Cửa sổ Settings |
| `Sources/Services` | Phím tắt toàn hệ thống, làm đẹp ảnh, watermark, cập nhật, thống kê |

## Ghi công

Shotly phát triển từ [Better Shot](https://github.com/KartikLabhshetwar/better-shot), dự án mã nguồn mở
của Kartik Labhshetwar, theo giấy phép BSD 3-Clause.

## Giấy phép

BSD 3-Clause. Xem [LICENSE](LICENSE).
