DEVICE=Pixel_9a
PACKAGE=com.auth0.guardian.sample
ADB=${ANDROID_HOME}/platform-tools/adb
#HTTP_PROXY=http://localhost:8118
#HTTP_PROXY=http://192.168.0.112:8118
#HTTP_PROXY=http://mac-mini:8118
#HTTP_PROXY=socks5://192.168.0.112:9050
#HTTP_PROXY=socks5://localhost:9050
HTTP_PROXY=socks5://localhost:1080

list-devices:
	${ANDROID_HOME}/cmdline-tools/latest/bin/avdmanager  list avd

boot:
	${ANDROID_HOME}/emulator/emulator -avd $(DEVICE) -dns-server 8.8.8.8 & #-http-proxy ${HTTP_PROXY} &

boot-headless:
	${ANDROID_HOME}/emulator/emulator -avd $(DEVICE) -no-window -gpu swiftshader_indirect -dns-server 8.8.8.8 & #-http-proxy ${HTTP_PROXY} &

deploy: install

install:
	./gradlew installDebug

start: run

run:
	$(ADB) shell am start -n $(PACKAGE)/.MainActivity

stop:
	$(ADB) shell am force-stop com.auth0.guardian.sample

bash: shell

shell:
	$(ADB) shell

log: tail

shutdown:
	$(ADB) emu kill

tail:
	${ANDROID_HOME}/platform-tools/adb logcat -s GuardianFCM

ping:
	${ANDROID_HOME}/platform-tools/adb shell ping google.com

rsync:
	rsync --progress --partial --no-links -av --stats . amin@mac-mini:/Users/amin/project/pg/guardian-bash/android