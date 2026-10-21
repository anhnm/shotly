# Cài Shotly Analytics trên Hostinger

## 1. Tạo database

Trong hPanel, mở `Websites` → `Manage` → `Databases` → `Management`, sau đó tạo database MySQL và user. Ghi lại đầy đủ tên database, username và password có prefix do Hostinger cấp.

## 2. Tạo bảng

Mở phpMyAdmin của database vừa tạo, chọn `Import`, tải file `bettershot-landing/analytics/schema.sql` lên và bấm `Go`.

## 3. Tạo khóa

Chạy hai lần lệnh sau trên Mac để lấy hai giá trị khác nhau:

```sh
openssl rand -hex 32
```

- Giá trị thứ nhất dùng làm `ingest_key`.
- Giá trị thứ hai dùng làm `rate_limit_salt`.

Tạo hash cho mật khẩu dashboard:

```sh
php -r "echo password_hash('MAT_KHAU_DASHBOARD', PASSWORD_DEFAULT), PHP_EOL;"
```

## 4. Cấu hình PHP

Giải nén `release/shotly-analytics-hostinger.zip` vào `public_html`. Kết quả cần có thư mục:

```text
public_html/
└── analytics/
    ├── admin/
    ├── events.php
    ├── schema.sql
    └── config.example.php
```

Copy `analytics/config.example.php` thành `analytics/config.php`, rồi nhập:

- Database host: thường là `localhost`, nhưng ưu tiên đúng giá trị Hostinger hiển thị.
- Database name, user và password ở bước 1.
- `ingest_key`, `rate_limit_salt` và `admin_password_hash` ở bước 3.

Không upload `config.php` lên Git. File `.htaccess` đi kèm chặn truy cập web trực tiếp vào cấu hình.

## 5. Kiểm tra dashboard

Mở:

```text
https://TEN-MIEN-CUA-ANH/analytics/admin/
```

Đăng nhập bằng mật khẩu gốc đã dùng để tạo hash. Dashboard có bộ lọc 7/30/90/365 ngày và nút xuất CSV.

## 6. Kết nối app Shotly

Mở `Resources/Info.plist` và điền:

```xml
<key>ShotlyAnalyticsEndpoint</key>
<string>https://TEN-MIEN-CUA-ANH/analytics/events.php</string>
<key>ShotlyAnalyticsIngestKey</key>
<string>INGEST_KEY_O_BUOC_3</string>
```

Endpoint bắt buộc dùng HTTPS. Nếu hai giá trị để trống, app sẽ không xếp hàng hoặc gửi analytics.

Tạo lại project và build:

```sh
xcodegen generate
make dmg
```

## 7. Test dữ liệu

1. Cài và mở DMG mới.
2. Kiểm tra `Settings` → `General` → `Privacy` đã bật `Share anonymous usage analytics`.
3. Chụp Region, dùng OCR và mở Editor chọn vài tool.
4. Đợi vài giây rồi refresh dashboard.

Shotly gửi theo batch nền và lưu hàng đợi cục bộ khi request thất bại. App không gửi ảnh, OCR text, clipboard, tên file, email hoặc tên người dùng. Nên cập nhật Privacy Policy trước khi phát hành bản có analytics.
