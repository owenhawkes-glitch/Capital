# MenuBento – build, bundle and run.
#
#   make run      build a debug .app and launch it
#   make settings same, and open Settings
#   make release  build an optimised .app in dist/
#   make install  release build, quit the running copy, replace
#                 /Applications/MenuBento.app and open it
#   make dmg      build dist/MenuBento.dmg (drag-to-Applications installer)
#   make icon     redraw Resources/AppIcon.icns
#   make cli      build menubento-cli (list items, test moves)
#   make clean
#
# Signing: ad-hoc by default. macOS ties Accessibility and Screen Recording
# grants to the signature, and an ad-hoc signature changes on every build,
# so grants get lost. With a stable identity in your keychain, put
#   SIGN_ID = MenuBento Dev
# in a local, untracked file named sign.mk (see README), or pass
#   make install SIGN_ID="MenuBento Dev"

-include sign.mk

APP        := MenuBento
BUNDLE     := dist/$(APP).app
CONTENTS   := $(BUNDLE)/Contents
CONFIG     ?= debug
BUILD_DIR  := .build/$(CONFIG)
SIGN_ID    ?= -

.PHONY: all build bundle run settings release install dmg icon cli clean

all: bundle

build:
	swift build -c $(CONFIG) --product $(APP)

bundle: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	cp Resources/AppIcon.icns "$(CONTENTS)/Resources/AppIcon.icns"
	cp "$(BUILD_DIR)/$(APP)" "$(CONTENTS)/MacOS/$(APP)"
	codesign --force --deep --sign "$(SIGN_ID)" "$(BUNDLE)"
	@echo "Built $(BUNDLE) (signed with: $(SIGN_ID))"

# Quit a running copy and wait until it has really gone.
define stop_app
	pkill -x $(APP) || true
	for i in $$(seq 1 40); do pgrep -x $(APP) >/dev/null || break; sleep 0.25; done
	! pgrep -x $(APP) >/dev/null || { echo "$(APP) is still running; quit it and try again."; exit 1; }
endef

run: bundle
	$(stop_app)
	open "$(BUNDLE)"

settings: bundle
	$(stop_app)
	open --env MENUBENTO_SETTINGS=1 "$(BUNDLE)"

release:
	$(MAKE) bundle CONFIG=release

install: release
	$(stop_app)
	rm -rf "/Applications/$(APP).app"
	cp -R "$(BUNDLE)" /Applications/
	open "/Applications/$(APP).app"
	@echo "Installed /Applications/$(APP).app (signed with: $(SIGN_ID))"

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

cli:
	swift build --product menubento-cli
	@echo "Run .build/debug/menubento-cli list"

clean:
	rm -rf .build dist
