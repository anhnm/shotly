# BetterShot Makefile
# Usage:
#   make build        — Debug build
#   make release      — Release build
#   make run          — Build and launch (debug)
#   make dmg          — Create unsigned DMG for local testing
#   make clean        — Remove build artifacts
#   make lint         — Swift compiler warnings check
#   make test-build   — Full clean + release build to verify everything compiles
#   make version      — Print current version
#   make ship V=1.0.33 NOTES="..." — Publish a release to GitHub (see release.sh)

SCHEME       = BetterShot
APP_NAME     = Shotly
PROJECT      = BetterShot.xcodeproj
CONFIG_DEBUG = Debug
CONFIG_REL   = Release
DERIVED_DIR  = .build
APP_DEBUG    = $(DERIVED_DIR)/Build/Products/$(CONFIG_DEBUG)/$(APP_NAME).app
APP_RELEASE  = $(DERIVED_DIR)/Build/Products/$(CONFIG_REL)/$(APP_NAME).app
VERSION     := $(shell python3 -c "import json; print(json.load(open('version.json'))['version'])")
DMG_NAME     = Shotly-$(VERSION).dmg
DMG_DIR      = release
# Sign with the stable self-signed identity when it exists (see tools/create-signing-cert.sh)
# so macOS keeps Screen Recording/Accessibility permissions across builds; otherwise ad-hoc.
SIGN_IDENTITY ?= $(shell security find-identity -p codesigning 2>/dev/null | grep -q '"Shotly Self-Signed"' && echo "Shotly Self-Signed" || echo "-")

.PHONY: build release run dmg clean lint test-build version ship help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

build: ## Debug build
	@echo "==> Building $(SCHEME) (Debug)..."
	@set -o pipefail; xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG_DEBUG) \
		-derivedDataPath $(DERIVED_DIR) \
		build 2>&1 | tail -3
	@echo "==> $(APP_DEBUG)"

release: ## Release build (unsigned)
	@echo "==> Building $(SCHEME) (Release)..."
	@set -o pipefail; xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG_REL) \
		-derivedDataPath $(DERIVED_DIR) \
		CODE_SIGNING_ALLOWED=NO \
		build 2>&1 | tail -3
	@# A build with signing disabled is only linker-signed: its identifier is the
	@# executable name and its resources are not sealed, so macOS cannot attach
	@# privacy permissions to it. Sign the whole bundle properly.
	@codesign --force --options runtime --timestamp=none \
		--entitlements Resources/BetterShot.entitlements \
		--sign "$(SIGN_IDENTITY)" "$(APP_RELEASE)"
	@codesign --verify --strict "$(APP_RELEASE)"
	@echo "==> $(APP_RELEASE) (signed: $(SIGN_IDENTITY))"

run: build ## Build and launch (debug)
	@echo "==> Launching Shotly..."
	@open "$(APP_DEBUG)"

dmg: release ## Create unsigned DMG for local testing
	@echo "==> Creating DMG..."
	@mkdir -p $(DMG_DIR)/staging
	@cp -R "$(APP_RELEASE)" $(DMG_DIR)/staging/
	@ln -sf /Applications $(DMG_DIR)/staging/Applications
	@hdiutil create -volname "Shotly" \
		-srcfolder $(DMG_DIR)/staging \
		-ov -format UDZO \
		"$(DMG_DIR)/$(DMG_NAME)" 2>/dev/null
	@rm -rf $(DMG_DIR)/staging
	@echo "==> $(DMG_DIR)/$(DMG_NAME)"

clean: ## Remove build artifacts
	@echo "==> Cleaning..."
	@rm -rf $(DERIVED_DIR)
	@rm -rf $(DMG_DIR)/staging
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean 2>/dev/null || true
	@echo "==> Clean."

lint: ## Check for compiler warnings
	@echo "==> Checking for warnings..."
	@set -o pipefail; xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG_DEBUG) \
		-derivedDataPath $(DERIVED_DIR) \
		build 2>&1 | grep -E "warning:|error:" || echo "No warnings."

test-build: clean release ## Full clean + release build
	@echo "==> Test build passed."

ship: ## Publish a release: make ship V=1.0.33 NOTES="Ghi chú"
	@./release.sh "$(V)" "$(NOTES)"

version: ## Print current version
	@echo "$(VERSION)"
