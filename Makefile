APP        := dist/DockStat.app
BIN        := $(APP)/Contents/MacOS/dockstat
INSTALL_TO := /Applications/DockStat.app
BUNDLE_ID  := dev.sonht.dockstat
ICNS       := Resources/DockStat.icns

.PHONY: build bundle sign run restart install uninstall clean perf bench verify icons logo panel

LOGO := docs/logo.png

build:
	swift build -c release

# The app icon is drawn from source, so it only needs re-rendering when the
# script changes — the .icns itself is committed.
$(ICNS): Scripts/make-icon.swift Scripts/make-icons.sh
	@bash Scripts/make-icons.sh

icons:
	@bash Scripts/make-icons.sh

# Same art as the .icns, as a single PNG for the README.
$(LOGO): Scripts/make-icon.swift
	@swift Scripts/make-icon.swift $(LOGO) 1024

logo: $(LOGO)

# Universal (arm64 + x86_64) when Xcode is available, native arch otherwise.
bundle: $(ICNS)
	@bash Scripts/package-app.sh

sign: bundle
	codesign --force -s - $(APP)

run: sign
	-pkill -f 'DockStat.app/Contents/MacOS/dockstat' 2>/dev/null || true
	open $(APP)

restart: sign
	-pkill -f 'DockStat.app/Contents/MacOS/dockstat' 2>/dev/null || true
	sleep 0.5
	open $(APP)

install: sign
	rm -rf $(INSTALL_TO)
	cp -R $(APP) $(INSTALL_TO)
	open $(INSTALL_TO)

uninstall:
	-pkill -f 'DockStat.app/Contents/MacOS/dockstat' || true
	rm -rf $(INSTALL_TO)
	launchctl bootout gui/$$UID/$(BUNDLE_ID) 2>/dev/null || true
	rm -f $$HOME/Library/LaunchAgents/$(BUNDLE_ID).plist

clean:
	swift package clean
	rm -rf build

perf:
	@bash Scripts/perf.sh $(ARGS)

bench: sign
	$(BIN) --bench

verify: sign
	$(BIN) --self-test
	$(BIN) --probe 3
	$(BIN) --render dist/icon-preview.png

panel: sign
	$(BIN) --panel dist/panel-preview.png
