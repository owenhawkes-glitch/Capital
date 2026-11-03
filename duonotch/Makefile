# DuoNotch – build, bundle and run.
#
#   make run      build a debug .app and launch it
#   make demo     launch with fake data (no Claude login needed)
#   make release  build an optimised .app in dist/
#   make install  copy the release .app to /Applications
#   make clean

APP        := DuoNotch
BUNDLE     := dist/$(APP).app
CONTENTS   := $(BUNDLE)/Contents
CONFIG     ?= debug
BUILD_DIR  := .build/$(CONFIG)

.PHONY: all build bundle run demo release install clean

all: bundle

build:
	swift build -c $(CONFIG)

bundle: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	cp "$(BUILD_DIR)/$(APP)" "$(CONTENTS)/MacOS/$(APP)"
	cp "$(BUILD_DIR)/duonotch-hook" "$(CONTENTS)/MacOS/duonotch-hook"
	# Ad-hoc signature so the keychain remembers "Always Allow" for this build.
	codesign --force --deep --sign - "$(BUNDLE)"
	@echo "Built $(BUNDLE)"

run: bundle
	pkill -x $(APP) || true
	open "$(BUNDLE)"

demo: bundle
	pkill -x $(APP) || true
	DUONOTCH_DEMO=1 open "$(BUNDLE)"

release:
	$(MAKE) bundle CONFIG=release

install: release
	rm -rf "/Applications/$(APP).app"
	cp -R "$(BUNDLE)" /Applications/
	@echo "Installed /Applications/$(APP).app – re-run 'Install hooks' in Settings so hooks point at the new path."

clean:
	rm -rf .build dist
