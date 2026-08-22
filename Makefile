EXEC     := Mumble
CONFIG   := debug

## Keep build products outside the project directory.
##
## Synced project folders can mutate files inside
## .build while the compiler is using them — producing "input file was modified during
## the build" on random object files, and occasionally a wedged swift-frontend stuck at
## 0% CPU. Moving the scratch path to ~/Library/Caches (never synced) removes the race.
SCRATCH  := $(HOME)/Library/Caches/MumbleBuild/scratch
BUILD    := $(SCRATCH)/$(CONFIG)/$(EXEC)

## Assemble and sign the bundle outside the project directory too.
##
## The project can live in an iCloud/file-provider synced folder. The provider
## stamps com.apple.FinderInfo onto files inside an .app faster than we can strip them,
## and codesign hard-refuses anything carrying them ("resource fork, Finder information,
## or similar detritus not allowed"). `xattr -cr` immediately before signing is not enough
## — the provider re-stamps in between. Staging in ~/Library/Caches sidesteps it entirely.
STAGE    := $(HOME)/Library/Caches/MumbleBuild
APPNAME  := Mumble.app
BUNDLE   := $(STAGE)/$(APPNAME)
CONTENTS := $(BUNDLE)/Contents

## TCC keys the Accessibility grant to the code signature, so an ad-hoc signature — which
## changes on every build — makes the user re-grant after every `make`. Prefer a stable
## Developer ID, then use an Apple Development identity for local builds. Fall back to
## ad-hoc ("-") only on a machine without either certificate.
SIGN_ID := $(shell { security find-identity -v -p codesigning 2>/dev/null \
			 | grep -E '"(Developer ID Application|Apple Development):' \
			 | head -1; } | sed -E 's/.*"(.*)".*/\1/')
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := -
endif

.PHONY: all build app run install clean icon

all: app

build:
	swift build -c $(CONFIG) --scratch-path "$(SCRATCH)"

## Regenerates AppIcon.icns from scripts/render-icon.swift. Not a dependency of `app` — the
## icon rarely changes and rendering 10 PNGs on every build is wasted time.
icon:
	@swift scripts/render-icon.swift
	@iconutil -c icns assets/AppIcon.iconset -o assets/AppIcon.icns
	@echo "wrote assets/AppIcon.icns"

## Assemble a real .app bundle. TCC (microphone + Accessibility) keys on bundle identity
## and code signature, so the raw SwiftPM binary can't be used directly.
app: build
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	@cp $(BUILD) "$(CONTENTS)/MacOS/$(EXEC)"
	@cp assets/Info.plist "$(CONTENTS)/Info.plist"
	@if [ -f assets/AppIcon.icns ]; then cp assets/AppIcon.icns "$(CONTENTS)/Resources/"; fi
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@# Belt and braces: the staging dir isn't synced, but the copied binary can still carry
	@# xattrs inherited from the synced .build directory.
	@xattr -cr "$(BUNDLE)"
	@codesign --force --sign "$(SIGN_ID)" \
		--entitlements assets/$(EXEC).entitlements \
		--options runtime \
		--timestamp=none \
		"$(BUNDLE)"
	@echo "built $(BUNDLE)  [signed: $(SIGN_ID)]"

## Only ever targets the Mumble executable.
run: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@echo "launching $(BUNDLE)"
	@open "$(BUNDLE)"

## Install to /Applications so the signed bundle path and Accessibility identity stay stable.
install: app
	@if [ -n "$${MUMBLE_BOOTSTRAP_PID:-}" ]; then \
		for pid in $$(pgrep -x "$(EXEC)" 2>/dev/null || true); do \
			if [ "$$pid" != "$${MUMBLE_BOOTSTRAP_PID}" ]; then kill "$$pid" 2>/dev/null || true; fi; \
		done; \
	else \
		pkill -x $(EXEC) 2>/dev/null || true; \
	fi
	@# $(BUNDLE) is an absolute staging path — the destination must use $(APPNAME) alone.
	@rm -rf "/Applications/$(APPNAME)"
	@cp -R "$(BUNDLE)" "/Applications/$(APPNAME)"
	@open -n "/Applications/$(APPNAME)"
	@echo "installed to /Applications/$(APPNAME)"

clean:
	@rm -rf .build "$(STAGE)" "$(SCRATCH)"
