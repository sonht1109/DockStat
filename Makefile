APP        := build/DockStat.app
BIN        := .build/release/dockstat
CONTENTS   := $(APP)/Contents
INSTALL_TO := /Applications/DockStat.app
BUNDLE_ID  := dev.sonht.dockstat

.PHONY: build bundle run restart install uninstall clean perf bench verify

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(BIN) $(CONTENTS)/MacOS/dockstat
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	codesign -s - --force --deep $(APP) 2>/dev/null || codesign -s - --force $(APP)
	@echo "bundled -> $(APP)"

run: bundle
	-pkill -f 'DockStat.app/Contents/MacOS/dockstat' 2>/dev/null || true
	open $(APP)

restart: bundle
	-pkill -f 'DockStat.app/Contents/MacOS/dockstat' 2>/dev/null || true
	sleep 0.5
	open $(APP)

install: bundle
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

bench: bundle
	$(APP)/Contents/MacOS/dockstat --bench

verify: bundle
	$(APP)/Contents/MacOS/dockstat --self-test
	$(APP)/Contents/MacOS/dockstat --probe 3
	$(APP)/Contents/MacOS/dockstat --render build/icon-preview.png
