.PHONY: build release clean setup-hooks

VERSION ?= 1.0.0
APP_NAME = FloatScreen
BUILD_DIR = build
ARCHIVE_PATH = $(BUILD_DIR)/$(APP_NAME).xcarchive
APP_PATH = $(BUILD_DIR)/$(APP_NAME).app
DMG_PATH = $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg
ZIP_PATH = $(BUILD_DIR)/$(APP_NAME)-$(VERSION).zip

setup-hooks:
	git config core.hooksPath scripts/git-hooks

build:
	xcodegen generate
	xcodebuild -project $(APP_NAME).xcodeproj \
		-scheme $(APP_NAME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR)/DerivedData \
		ARCHS="arm64 x86_64" \
		ONLY_ACTIVE_ARCH=NO \
		MARKETING_VERSION=$(VERSION) \
		CURRENT_PROJECT_VERSION=$(VERSION) \
		CODE_SIGN_IDENTITY="-" \
		build
	@echo "Built $(APP_NAME) $(VERSION)"

release: build
	# Create ZIP for Sparkle
	@mkdir -p $(BUILD_DIR)
	@rm -f $(ZIP_PATH)
	cd $(BUILD_DIR)/DerivedData/Build/Products/Release && \
		ditto -c -k --keepParent $(APP_NAME).app $(abspath $(ZIP_PATH))
	@echo "Created $(ZIP_PATH)"
	# Create DMG
	@rm -f $(DMG_PATH)
	hdiutil create -volname "$(APP_NAME)" \
		-srcfolder $(BUILD_DIR)/DerivedData/Build/Products/Release/$(APP_NAME).app \
		-ov -format UDZO $(DMG_PATH)
	@echo "Created $(DMG_PATH)"
	@echo ""
	@echo "=== Next steps ==="
	@echo "1. Sign the update:  sign_update $(ZIP_PATH)"
	@echo "2. Update appcast.xml with the signature and version"
	@echo "3. Create GitHub release:"
	@echo "   gh release create v$(VERSION) $(ZIP_PATH) $(DMG_PATH) --title 'v$(VERSION)' --notes 'Release $(VERSION)'"

clean:
	rm -rf $(BUILD_DIR) $(APP_NAME).xcodeproj
