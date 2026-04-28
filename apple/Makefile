MEMBER_ID = S85GF78CAS
NAME      = Amin Abbaspour
APP_NAME  = PushListenerApp.app
BINARY    = $(APP_NAME)/Contents/MacOS/PushListener

.DEFAULT_GOAL := build
.PHONY: build sign verify run log clean

# ── Default goal ──────────────────────────────────────────────────────────────
build: $(BINARY) $(APP_NAME)/Contents/Info.plist sign

# ── Compile (only when main.swift is newer than the binary) ───────────────────
$(BINARY): main.swift
	mkdir -p $(APP_NAME)/Contents/MacOS
	swiftc -target arm64-apple-macos11.0 main.swift -o $@

# ── Copy Info.plist into bundle (only when source plist is newer) ─────────────
$(APP_NAME)/Contents/Info.plist: Info.plist
	mkdir -p $(APP_NAME)/Contents
	cp $< $@

# ── Code-sign (phony → always runs as part of build; also callable standalone) ─
sign:
	codesign --force --deep --options runtime --entitlements push.entitlements \
	    -s "Apple Development: $(NAME) ($(MEMBER_ID))" $(APP_NAME)

# ── Verify signature ──────────────────────────────────────────────────────────
verify:
	codesign -vvv $(APP_NAME)
	codesign -d --entitlements :- $(BINARY)

# ── Run / stream logs ─────────────────────────────────────────────────────────
run:
	./$(BINARY)

log:
	log stream --predicate 'processImagePath contains "$(APP_NAME)"'

# ── Remove build artifact ─────────────────────────────────────────────────────
clean:
	rm -rf $(APP_NAME)
