APP := build/KindleToPDF.app
BUNDLE_ID := jp.local.KindleToPDF
# Where `make install` puts the app. Override with INSTALL_DIR=~/Applications.
INSTALL_DIR ?= /Applications
INSTALLED := $(INSTALL_DIR)/KindleToPDF.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: app test run install uninstall where clean

app:
	./scripts/build-app.sh

test:
	swift test

# Opens the installed app if there is one, otherwise the build in build/
# (building it first if needed). Opening build/ registers that copy with
# Launchpad, which is why `make install` unregisters it again.
run:
	@if [ -d "$(INSTALLED)" ]; then open "$(INSTALLED)"; \
	else test -d $(APP) || $(MAKE) app; open $(APP); fi

# Copies the app into the Applications folder so it shows up in Launchpad
# and Spotlight. Replaces any previous install, removes the build/ copy from
# Launchpad so only one KindleToPDF is listed, and restarts the Dock so
# Launchpad picks up the new icon.
install:
	@test -d $(APP) || $(MAKE) app
	@if [ ! -w "$(INSTALL_DIR)" ]; then \
		echo "error: $(INSTALL_DIR) is not writable. Try: make install INSTALL_DIR=~/Applications" >&2; exit 1; \
	fi
	rm -rf "$(INSTALLED)"
	cp -R $(APP) "$(INSTALLED)"
	-$(LSREGISTER) -u $(APP) >/dev/null 2>&1
	rm -rf $(APP)
	-$(LSREGISTER) -f "$(INSTALLED)" >/dev/null 2>&1
	-touch "$(INSTALLED)"
	-killall Dock >/dev/null 2>&1
	@echo "Installed: $(INSTALLED)"
	@echo "Launchpad / Spotlight / Finder の「アプリケーション」から起動できます。"
	@echo "初回起動後、システム設定で画面収録とアクセシビリティを許可してください。"
	@$(MAKE) --no-print-directory where

uninstall:
	rm -rf "$(INSTALLED)"
	-$(LSREGISTER) -u "$(INSTALLED)" >/dev/null 2>&1
	-killall Dock >/dev/null 2>&1
	@echo "Removed: $(INSTALLED)"

# Lists every copy of the app macOS knows about. More than one line here
# means Launchpad will show duplicates; delete the extras.
where:
	@echo "KindleToPDF の場所:"
	@mdfind "kMDItemCFBundleIdentifier == '$(BUNDLE_ID)'" | sed 's/^/  /'
	@echo "(2つ以上ある場合は、残したいもの以外を削除してください)"

clean:
	rm -rf .build build
