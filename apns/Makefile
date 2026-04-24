goad: compile

MEMBER_ID=S85GF78CAS
NAME=Amin Abbaspour

compile: main.swift
	swiftc -target arm64-apple-macos11.0 main.swift -o PushListenerApp.app/Contents/MacOS/PushListener

sign:
	codesign --force --deep --options runtime --entitlements push.entitlements -s "Apple Development: ${NAME} (${MEMBER_ID})" PushListenerApp.app

verify:
	codesign -vvv PushListenerApp.app
	codesign -d --entitlements :- PushListenerApp.app/Contents/MacOS/PushListener

run:
	./PushListenerApp.app/Contents/MacOS/PushListener

log:
	log stream --predicate 'processImagePath contains "PushListener"'