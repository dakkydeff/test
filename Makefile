APP := build/KindleToPDF.app
# Where `make install` puts the app. Override with INSTALL_DIR=~/Applications.
INSTALL_DIR ?= /Applications

.PHONY: app test run install uninstall clean

app:
	./scripts/build-app.sh

test:
	swift test

# Opens the existing bundle; builds it first only if it is missing
# (rebuilding re-signs the app, which may reset its TCC permissions).
run:
	@test -d $(APP) || $(MAKE) app
	open $(APP)

# Copies the app into the Applications folder so it shows up in Launchpad
# and Spotlight. Replaces any previous install.
install:
	@test -d $(APP) || $(MAKE) app
	@if [ ! -w "$(INSTALL_DIR)" ]; then \
		echo "error: $(INSTALL_DIR) is not writable. Try: make install INSTALL_DIR=~/Applications" >&2; exit 1; \
	fi
	rm -rf "$(INSTALL_DIR)/KindleToPDF.app"
	cp -R $(APP) "$(INSTALL_DIR)/KindleToPDF.app"
	@echo "Installed: $(INSTALL_DIR)/KindleToPDF.app"
	@echo "Launchpad / Spotlight / Finder の「アプリケーション」から起動できます。"
	@echo "初回起動後、システム設定で画面収録とアクセシビリティを許可してください。"

uninstall:
	rm -rf "$(INSTALL_DIR)/KindleToPDF.app"
	@echo "Removed: $(INSTALL_DIR)/KindleToPDF.app"

clean:
	rm -rf .build build
