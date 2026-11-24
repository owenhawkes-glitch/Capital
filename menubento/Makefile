# MenuBento – build, bundle and run.
#
#   make run      build a debug .app and launch it
#   make settings same, and open Settings
#   make release  build an optimised .app in dist/
#   make install  copy the release .app to /Applications
#   make cli      build menubento-cli (list items, test moves)
#   make clean
#
# Signing: ad-hoc by default. macOS ties Accessibility and Screen Recording
# grants to the signature, and an ad-hoc signature changes on every build,
# so grants get lost. With a stable identity in your keychain:
#   make run SIGN_ID="MenuBento Dev"
# or put SIGN_ID in a local, untracked file named sign.mk (see MORNING.md).

-include sign.mk

APP        := MenuBento
BUNDLE     := dist/$(APP).app
CONTENTS   := $(BUNDLE)/Contents
CONFIG     ?= debug
BUILD_DIR  := .build/$(CONFIG)
SIGN_ID    ?= -

.PHONY: all build bundle run settings release install cli clean

all: bundle

build:
	swift build -c $(CONFIG) --product $(APP)

bundle: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	cp "$(BUILD_DIR)/$(APP)" "$(CONTENTS)/MacOS/$(APP)"
	codesign --force --deep --sign "$(SIGN_ID)" "$(BUNDLE)"
	@echo "Built $(BUNDLE) (signed with: $(SIGN_ID))"

# Quit a running copy and wait until it has really gone.
define stop_app
	pkill -x $(APP) || true
	for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x $(APP) >/dev/null || break; sleep 0.3; done
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
	rm -rf "/Applications/$(APP).app"
	cp -R "$(BUNDLE)" /Applications/
	@echo "Installed /Applications/$(APP).app"

cli:
	swift build --product menubento-cli
	@echo "Run .build/debug/menubento-cli list"

clean:
	rm -rf .build dist
