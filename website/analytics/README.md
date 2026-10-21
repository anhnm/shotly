# Shotly first-party analytics

This directory is ready to upload to `public_html/analytics` on Hostinger.

1. Create a MySQL database and user in hPanel.
2. Import `schema.sql` with phpMyAdmin.
3. Copy `config.example.php` to `config.php` and enter the database credentials, ingest key, admin password hash and rate-limit salt.
4. Upload this directory to `public_html/analytics`.
5. Test `https://YOUR-DOMAIN/analytics/admin/` and sign in.
6. Put the same endpoint and ingest key in Shotly's `Info.plist`, then rebuild the app.

Generate random values on macOS:

```sh
openssl rand -hex 32
```

Generate the dashboard password hash:

```sh
php -r "echo password_hash('YOUR_ADMIN_PASSWORD', PASSWORD_DEFAULT), PHP_EOL;"
```

The endpoint intentionally accepts only a fixed event list. It does not accept OCR text, file paths, image data, clipboard contents, names, email addresses or other free-form personal content. Web-server access logs may still be retained by the hosting provider according to its own configuration.
