#!/usr/bin/env bash
# Tạo chứng chỉ ký code tự ký "Shotly Self-Signed" trong Keychain đăng nhập.
#
#   ./tools/create-signing-cert.sh
#
# Vì sao cần: bản build ký ad-hoc có chữ ký khác nhau mỗi lần build, nên sau mỗi lần
# cập nhật macOS coi Shotly là app mới và bắt cấp lại quyền Screen Recording /
# Accessibility. Ký mọi bản bằng cùng một chứng chỉ thì quyền được giữ nguyên.
#
# Chạy một lần trên máy dùng để phát hành. macOS sẽ hỏi mật khẩu để tin cậy chứng chỉ.
# Sao lưu file .p12 mà script tạo ra: mất chứng chỉ thì bản sau sẽ lại bị mất quyền.
set -euo pipefail

NAME="${SHOTLY_SIGN_IDENTITY:-Shotly Self-Signed}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
BACKUP_DIR="$HOME/Documents/Shotly Signing"
OPENSSL=/usr/bin/openssl

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
  echo "✓ Chứng chỉ \"$NAME\" đã có sẵn, không cần tạo lại."
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no

[dn]
CN = $NAME

[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

echo "▶ Tạo khoá và chứng chỉ (hạn 10 năm)…"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

PASSWORD=$(uuidgen)
LEGACY=()
# OpenSSL 3 needs -legacy for a .p12 that macOS `security import` can read.
PKCS12_HELP=$("$OPENSSL" pkcs12 -help 2>&1 || true)
if [[ "$PKCS12_HELP" == *-legacy* ]]; then LEGACY=(-legacy); fi
"$OPENSSL" pkcs12 -export ${LEGACY[@]+"${LEGACY[@]}"} -name "$NAME" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" -passout "pass:$PASSWORD"

echo "▶ Thêm vào Keychain đăng nhập…"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null

echo "▶ Tin cậy chứng chỉ cho việc ký code (macOS sẽ hỏi mật khẩu)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

mkdir -p "$BACKUP_DIR"
cp "$WORK/identity.p12" "$BACKUP_DIR/$NAME.p12"
printf '%s\n' "$PASSWORD" > "$BACKUP_DIR/$NAME - password.txt"
chmod 600 "$BACKUP_DIR/$NAME.p12" "$BACKUP_DIR/$NAME - password.txt"

security find-identity -p codesigning | grep -q "\"$NAME\"" || { echo "❌ Không tìm thấy chứng chỉ sau khi tạo." >&2; exit 1; }
echo "✓ Đã tạo chứng chỉ \"$NAME\"."
echo "  Bản sao lưu: $BACKUP_DIR (giữ cẩn thận, KHÔNG đưa lên Git)."
echo "  Máy khác muốn phát hành: mở file .p12 bằng Keychain Access, nhập mật khẩu trong file password.txt."
