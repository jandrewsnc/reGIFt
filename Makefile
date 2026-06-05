SCHEME    = reGIFt
CONFIG    = Release
BUILD_DIR = build

.PHONY: build install clean

build:
	xcodebuild \
		-project reGIFt.xcodeproj \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR) \
		build

install: build
	@APP="$(BUILD_DIR)/Build/Products/$(CONFIG)/$(SCHEME).app"; \
	cp -r "$$APP" "/Applications/$(SCHEME).app" && \
	echo "Installed to /Applications/$(SCHEME).app" && \
	echo "Launch it once — it will register itself as a Login Item automatically."

clean:
	rm -rf $(BUILD_DIR)
