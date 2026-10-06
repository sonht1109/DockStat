APP        := dist/DockStat.app
BIN        := $(APP)/Contents/MacOS/dockstat
INSTALL_TO := /Applications/DockStat.app
BUNDLE_ID  := dev.sonht.dockstat

.PHONY: build bundle sign run restart install uninstall clean perf bench verify

build:
	swift build -c release

# Universal (arm64 + x86_64) when Xcode is available, native arch otherwise.
bundle:
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
