# Tổng Hợp Các Thay Đổi & Nâng Cấp Trên Shotly (v1.0.31)

Dưới đây là tài liệu tổng hợp toàn bộ các tính năng mới, lỗi đã sửa, tối ưu hóa hiệu năng và cập nhật tài nguyên đã được triển khai cho ứng dụng **Shotly** (Phiên bản **1.0.31**, Build **32**).

---

## 1. Nút sao chép văn bản gốc tại Popup dịch OCR (Mới - v1.0.31)
* **Bổ sung nút sao chép văn bản gốc (Original):**
  * Thiết kế lại cấu trúc cột trái (Original text column) của giao diện **OCR Translation** (`OCRTranslationWindow.swift`).
  * Thêm nút bấm **`Copy original`** (biểu tượng sao chép tài liệu `doc.on.doc`) giúp người dùng copy văn bản gốc bên ô Textarea sang clipboard ngay lập tức trước hoặc sau khi chỉnh sửa/dịch lại.
  * Sắp xếp bố cục header cột trái đối xứng hoàn hảo với cột dịch thuật tiếng Việt bên phải.

---

## 2. Hệ Thống OCR Dịch Thuật Tích Hợp (Mới - v1.0.30)
* **Dịch thuật tức thì sau khi OCR:** 
  * Phát triển cửa sổ **OCR Translation** (`OCRTranslationWindow`) kết hợp khung dịch thuật gốc của Apple (`Translation` framework trên macOS 15.0+).
  * Khi bật tính năng trong cấu hình, bất kỳ văn bản nào được trích xuất từ ảnh chụp (OCR) sẽ được hiển thị ngay lập tức trong bảng dịch nổi phía góc phải màn hình, hỗ trợ chuyển ngữ sang tiếng Việt hoặc các ngôn ngữ mục tiêu khác.
  * Hỗ trợ sao chép bản dịch trực tiếp hoặc đóng bảng bằng phím tắt. Các máy chạy macOS 14 trở xuống sẽ tự động chuyển về chế độ Toast thông báo sao chép văn bản gốc bình thường.

---

## 3. Hệ Thống Analytics Tự Quản Lý Trên Hostinger (Mới - v1.0.30)
* **Analytics ẩn danh, bảo mật:**
  * Xây dựng dịch vụ **AnalyticsService** gọn nhẹ, lưu trữ hàng đợi cục bộ dưới máy và gửi báo cáo ẩn danh (event telemetry) dạng batch về máy chủ.
  * Hoàn toàn không lưu hoặc gửi dữ liệu nhạy cảm của người dùng (không gửi ảnh chụp, nội dung văn bản OCR, clipboard, tên tệp, email hay tên tài khoản).
  * Triển khai bộ mã nguồn PHP backend trong thư mục `website/analytics` để tự quản lý lưu trữ trên cơ sở dữ liệu MySQL của Hostinger, đi kèm trang Dashboard quản trị lọc dữ liệu theo thời gian thực (7/30/90/365 ngày) và xuất file CSV.
  * Cho phép người dùng tùy chọn bật/tắt chia sẻ phân tích ẩn danh này tại phần cấu hình **Settings -> General -> Privacy**.

---

## 4. Quản Lý Lưu Trữ Ảnh Chụp Linh Hoạt (Mới - v1.0.30)
* **Bộ chọn điểm xuất tệp tin (ImageSavePanel):**
  * Tích hợp lớp helper `ImageSavePanel` để mở hộp thoại lưu tệp (`NSSavePanel`) mặc định của macOS khi xuất ảnh hoặc lưu ảnh chụp.
  * Tự động nhận diện thư mục lưu trữ ưa thích thiết lập trong cấu hình ứng dụng, định dạng đuôi tệp xuất ra (PNG, JPEG) cùng mức chất lượng nén mong muốn của người dùng.

---

## 5. Tối Ưu Hóa & Bản Địa Hóa Landing Page (Mới - v1.0.30)
* **Chuyển đổi tên miền & SEO:**
  * Đồng bộ toàn bộ liên kết trên trang và trong các tệp cấu hình SEO sang tên miền chính thức mới: **`https://shotly.anhnm.pro/`**.
  * Bổ sung tệp chỉ mục tìm kiếm tự động **`sitemap.xml`** và chỉ dẫn cấu trúc cào dữ liệu **`robots.txt`** chuẩn SEO.
* **Hỗ trợ đa ngôn ngữ (Localization):**
  * Tạo thêm thư mục bản dịch tiếng Việt `/vi/` với tệp `index.html` bản địa hóa riêng, giúp người dùng trong nước dễ dàng tiếp cận tính năng.
* **Giao diện Hero Section rộng toàn màn hình:**
  * Loại bỏ lớp giới hạn kích thước `.section-shell` khỏi thẻ `<section class="hero">` và bọc nội dung bên trong một khối `<div class="section-shell">` riêng biệt. Giúp các vòng phát sáng nền trang trí (`.hero-glow-one` và `.hero-glow-two`) tự động giãn rộng 100% kích thước bề ngang màn hình (Full Width).
  * Thay thế mockup cũ bằng ảnh sản phẩm thực tế: **`public/editor.webp`**.
  * Đăng ký Credit chân trang: **`Based on Better Shot, an open-source project by Kartik Labhshetwar.`**

---

## 6. Bản dịch tiếng Anh màn hình Editor & Liên kết Facebook
* **Dịch tiếng Anh màn hình khởi đầu Editor:**
  * Toàn bộ nhãn văn bản và các nút chụp/quay mặc định khi mở Editor trống đã được chuyển đổi hoàn toàn sang tiếng Anh: `"Drag and drop or paste screenshot"`, `"Or use keyboard shortcuts to capture"`, `"Full Screen"`, `"Window"`, `"Region"`, `"Record GIF"`.
* **Liên kết Facebook tác giả:**
  * Tại phần thông tin **Upgraded by** trong tab **Settings -> About**, thay thế số điện thoại bằng liên kết trực tiếp tới trang cá nhân: **`Anh Nguyễn - Facebook`** (`https://www.facebook.com/anh2610/`).

---

## 7. Thiết Kế Slick Web-UI Cho "Buy Me a Coffee"
Cập nhật giao diện và bố cục cấu trúc tính năng Buy Me a Coffee khớp 100% với giao diện web thiết kế của bạn:
* **Giao diện Form nhập liệu:** Viền xanh lục đậm nổi bật, Stepper tăng giảm tiện lợi, phím chọn mệnh giá nhanh, nội dung chuyển khoản tự động loại bỏ dấu tiếng Việt để tránh lỗi thanh toán.
* **Giao diện Cảm ơn (Thank You Screen):** Tiêu đề `"Thank you from the bottom of my heart."` và mô tả tri ân được thiết kế tự động xuống dòng đầy đủ không bị cắt lửng. Mã QR đặt nổi bật trong khung nền trắng có bóng đổ mềm sang trọng, đi kèm bảng tổng hợp thông tin chuyển khoản dạng lưới.

---

## 8. Màn Hình Onboarding 3 Bước (Khởi Chạy Lần Đầu)
Thiết kế cửa sổ Onboarding chuyên biệt (`OnboardingWindowController`) với Dark Card, bo góc 14pt, viền trắng mờ 12%:
* **Bước 1 — Welcome & Features:** Logo bo góc, tiêu đề và lưới 2 cột giới thiệu 10 tính năng cốt lõi.
* **Bước 2 — Cấp Quyền Hệ Thống:** Nhận diện tự động quyền Quay màn hình và Trợ năng ngay khi người dùng cấp quyền.
* **Bước 3 — Phím Tắt & Cảnh Báo Trùng Lặp:** Hiển thị thẻ phím tắt hiện tại, cảnh báo màu cam nổi bật nếu phím tắt bị trùng với phím mặc định của macOS (`⌘⇧3/⌘⇧4/⌘⇧5`).

---

## 9. Nâng Cấp Giao Diện Cài Đặt (Settings Window)
* **Sidebar chính xác:** Sửa lỗi lệch chữ/mất chữ cái đầu ở Sidebar bằng cấu trúc HStack thủ công.
* **Thanh cuộn:** Bọc Form các tab General, Capture, Recording vào ScrollView tránh mất nội dung trên màn hình độ phân giải thấp.
* **Kích thước rộng rãi:** Mở rộng kích thước cửa sổ cài đặt lên `760x580` giúp các nút và thanh trượt hiển thị trực quan.

---

## 10. Tương Thích Hoàn Hảo Với Dark Mode Hệ Thống
* Loại bỏ thuộc tính cưỡng bức Light Mode `NSRequiresAquaSystemAppearance` trong `Info.plist`.
* Cho phép Shotly đồng bộ và chuyển đổi giao diện sáng/tối tức thì theo chế độ hệ thống macOS trong thời gian thực.

---

## 11. Tối Ưu Hóa Trải Nghiệm Chụp Vùng (Region Capture)
* **Tọa Độ Thời Gian Thực:** Hiển thị liên tục tọa độ tâm quay chuột `X / Y` cạnh con trỏ.
* **Di Chuyển Khung Bằng Phím Cách (Spacebar):** Đè phím `Space` khi đang kéo để di chuyển vùng chọn.
* **Tăng Tốc Chụp Đóng Băng:** Viết lại luồng chụp ảnh màn hình bằng Swift 6 strict concurrency, loại bỏ hoàn toàn độ trễ trích xuất hình ảnh.

---

## 12. Quản Lý Đóng Dấu (Watermark) Linh Hoạt
* **Preset Watermark:** Cấu hình đóng dấu chữ/ảnh linh hoạt với các thông số vị trí, góc xoay, kích thước và độ mờ.
* **Nút Add More...:** Bổ sung nút liên kết nhanh ở popover toolbar editor giúp chuyển thẳng người dùng tới tab Watermark trong cài đặt.

---

## 13. Cập Nhật Tài Nguyên & Phiên Bản
* **Hình Nền Mới:** Đăng ký nhận diện 10 ảnh nền mới dạng `.jpg` (từ `mac-asset-1` đến `mac-asset-10`).
* **Icon mới:** Đồng bộ bộ icon mới trong danh mục Xcode Assets.
* **Đóng gói DMG:** Biên dịch và đóng gói hoàn tất tệp cài đặt chính thức:
  👉 **`release/Shotly-1.0.31.dmg`**
