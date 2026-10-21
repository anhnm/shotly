#!/usr/bin/env bash
# Phát hành bản Shotly mới cho mọi người (app tự thấy và cập nhật).
#
#   ./release.sh 1.0.33 "Thêm zoom trong editor" "Sửa lỗi chụp vùng"   # bản thường
#   ./release.sh 1.0.33 "Sửa lỗi nghiêm trọng" --force                  # bắt buộc mọi người cập nhật
#   ./release.sh 1.0.33 "Thử nghiệm" --dry-run                          # chỉ build + tạo file, không đăng
#
# Cần: GitHub CLI đã đăng nhập (brew install gh && gh auth login),
#      Resources/Info.plist có ShotlyUpdateRepo = chủ/tên-repo (repo public, đã push code),
#      chứng chỉ ký "Shotly Self-Signed" trong Keychain (tạo bằng ./tools/create-signing-cert.sh).
#      Đổi tên chứng chỉ bằng biến SHOTLY_SIGN_IDENTITY nếu cần.
set -euo pipefail
cd "$(dirname "$0")"

die() { echo "❌ $*" >&2; exit 1; }

VERSION="${1:-}"; [[ -n "$VERSION" ]] || die "Thiếu số phiên bản. Ví dụ: ./release.sh 1.0.33 \"Ghi chú\""
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || die "Phiên bản phải dạng 1.0.33"
shift
FORCE=0; DRY=0; NOTES=()
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    --dry-run) DRY=1 ;;
    *) NOTES+=("$a") ;;
  esac
done
[[ ${#NOTES[@]} -gt 0 ]] || NOTES=("Cải thiện và sửa lỗi")

APP_NAME=Shotly
IDENTITY="${SHOTLY_SIGN_IDENTITY:-Shotly Self-Signed}"
REPO=$(/usr/libexec/PlistBuddy -c "Print :ShotlyUpdateRepo" Resources/Info.plist 2>/dev/null | tr -d '[:space:]' || true)
[[ -n "$REPO" ]] || die "Chưa cấu hình repo: thêm ShotlyUpdateRepo vào Resources/Info.plist"

OLD_VERSION=$(python3 -c "import json;print(json.load(open('version.json'))['version'])")
OLD_BUILD=$(python3 -c "import json;print(json.load(open('version.json'))['build'])")
BUILD=$((OLD_BUILD + 1))
[[ "$(printf '%s\n%s\n' "$OLD_VERSION" "$VERSION" | sort -V | tail -1)" == "$VERSION" && "$VERSION" != "$OLD_VERSION" ]] \
  || die "Phiên bản $VERSION phải lớn hơn bản hiện tại $OLD_VERSION"

if [[ "$IDENTITY" == "-" ]]; then
  # Chỉ để thử: ký ad-hoc thì người dùng sẽ phải cấp lại quyền sau khi cập nhật.
  [[ $DRY -eq 1 ]] || die "Ký ad-hoc (SHOTLY_SIGN_IDENTITY=-) chỉ dùng với --dry-run"
  echo "⚠️  Ký ad-hoc (chỉ để thử)"
else
  security find-identity -p codesigning | grep -q "\"$IDENTITY\"" \
    || die "Không thấy chứng chỉ ký \"$IDENTITY\". Chạy ./tools/create-signing-cert.sh trước."
fi
command -v xcodegen >/dev/null || die "Chưa cài XcodeGen: brew install xcodegen"
if [[ $DRY -eq 0 ]]; then
  command -v gh >/dev/null || die "Chưa cài GitHub CLI: brew install gh && gh auth login"
  gh auth status >/dev/null 2>&1 || die "GitHub CLI chưa đăng nhập: gh auth login"
  gh repo view "$REPO" >/dev/null 2>&1 || die "Không thấy repo $REPO trên GitHub (đã tạo và push code chưa?)"
  ! gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1 || die "Bản v$VERSION đã tồn tại trên $REPO"
fi

# ---- đặt phiên bản (trả lại như cũ nếu build lỗi) ----
cp project.yml project.yml.bak
cp version.json version.json.bak
restore_version() {
  mv project.yml.bak project.yml
  mv version.json.bak version.json
  xcodegen generate --quiet >/dev/null 2>&1 || true
}
trap 'restore_version; die "Build lỗi (đã trả lại phiên bản cũ)"' ERR
sed -i '' -E "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$VERSION\"/; s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$BUILD\"/" project.yml
xcodegen generate --quiet
echo "▶ Phiên bản $VERSION (build $BUILD)"

# ---- build bản Release ----
xcodebuild -project BetterShot.xcodeproj -scheme BetterShot -configuration Release \
  -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build -quiet
APP=".build/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || false

# ---- ký bằng chứng chỉ cố định: macOS giữ quyền Screen Recording/Accessibility qua các bản ----
codesign --force --options runtime --timestamp=none \
  --entitlements Resources/BetterShot.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
trap - ERR

# ---- đóng gói DMG ----
mkdir -p release
DMG="release/$APP_NAME-$VERSION.dmg"
STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGING"
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
SIZE=$(stat -f%z "$DMG")

# minBuild: --force → mọi bản cũ phải cập nhật; không thì giữ như bản trước
PREV_MIN=$(python3 -c "import json;print(json.load(open('version.json')).get('minBuild',0))")
MIN=$([[ $FORCE -eq 1 ]] && echo "$BUILD" || echo "$PREV_MIN")

python3 - "$VERSION" "$BUILD" "$REPO" "$SHA" "$SIZE" "$MIN" "${NOTES[@]}" <<'PY'
import json, sys
v, build, repo, sha, size, mn, *notes = sys.argv[1:]
manifest = {
    "version": v,
    "build": int(build),
    "minimumOS": "14.0",
    "dmgUrl": f"https://github.com/{repo}/releases/download/v{v}/Shotly-{v}.dmg",
    "sha256": sha,
    "size": int(size),
    "notes": notes,
    "minBuild": int(mn),
}
for path in ("release/version.json", "version.json"):
    with open(path, "w") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")
PY
echo "▶ $DMG ($((SIZE / 1024 / 1024)) MB) · sha256 ${SHA:0:12}…"

if [[ $DRY -eq 1 ]]; then
  restore_version
  echo "✓ Dry-run xong (chưa đăng, đã trả lại phiên bản $OLD_VERSION). File: $DMG, release/version.json"
  exit 0
fi
rm -f project.yml.bak version.json.bak

# ---- đăng lên GitHub Releases (app đọc releases/latest/download/version.json) ----
BODY=$(printf -- '- %s\n' "${NOTES[@]}")
gh release create "v$VERSION" "$DMG" release/version.json \
  --repo "$REPO" --title "$APP_NAME $VERSION" --notes "$BODY" --latest
echo "✓ Đã phát hành v$VERSION → https://github.com/$REPO/releases/tag/v$VERSION"
echo "  Mọi người mở app sẽ thấy thông báo cập nhật (hoặc Settings → About → Check for Updates)."
echo "  Nhớ commit thay đổi phiên bản: git commit -am \"Release $VERSION\" && git push"
