# DuoNotch – build, bundle and run.
#
#   make run      build a debug .app and launch it
#   make demo     launch with fake data (no Claude login needed)
#   make release  build an optimised .app in dist/
#   make install  copy the release .app to /Applications and open it
#   make dmg      build dist/DuoNotch.dmg (drag-to-Applications installer)
#   make icon     redraw Resources/AppIcon.icns
#   make clean

APP        := DuoNotch
BUNDLE     := dist/$(APP).app
CONTENTS   := $(BUNDLE)/Contents
CONFIG     ?= debug
BUILD_DIR  := .build/$(CONFIG)

.PHONY: all build bundle run demo release install dmg icon clean

all: bundle

build:
	swift build -c $(CONFIG)

bundle: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	cp Resources/AppIcon.icns "$(CONTENTS)/Resources/AppIcon.icns"
	cp "$(BUILD_DIR)/$(APP)" "$(CONTENTS)/MacOS/$(APP)"
	cp "$(BUILD_DIR)/duonotch-hook" "$(CONTENTS)/MacOS/duonotch-hook"
	# Ad-hoc signature so the keychain remembers "Always Allow" for this build.
	codesign --force --deep --sign - "$(BUNDLE)"
	@echo "Built $(BUNDLE)"

# Quit a running copy and wait until it has really gone, otherwise
# `open` can fail with error -600 while the old process is still exiting.
define stop_app
	pkill -x $(APP) || true
	for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x $(APP) >/dev/null || break; sleep 0.3; done
endef

run: bundle
	$(stop_app)
	open "$(BUNDLE)"

demo: bundle
	$(stop_app)
	open --env DUONOTCH_DEMO=1 "$(BUNDLE)"

release:
	$(MAKE) bundle CONFIG=release

install: release
	$(stop_app)
	rm -rf "/Applications/$(APP).app"
	cp -R "$(BUNDLE)" /Applications/
	open "/Applications/$(APP).app"
	@echo "Installed /Applications/$(APP).app (hooks repoint to it automatically on launch)."

dmg: release
	rm -rf dist/dmg "dist/$(APP).dmg"
	mkdir -p dist/dmg
	cp -R "$(BUNDLE)" dist/dmg/
	ln -s /Applications dist/dmg/Applications
	hdiutil create -volname "$(APP)" -srcfolder dist/dmg -ov -format UDZO "dist/$(APP).dmg"
	rm -rf dist/dmg
	@echo "Built dist/$(APP).dmg"

icon:
	swift Scripts/make-icon.swift

clean:
	rm -rf .build dist
