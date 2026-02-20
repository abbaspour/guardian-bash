DEVICE=Pixel_9a
PACKAGE=com.auth0.guardian.sample
ADB=${ANDROID_HOME}/platform-tools/adb

list-devices:
	${ANDROID_HOME}/cmdline-tools/latest/bin/avdmanager  list avd

boot:
	${ANDROID_HOME}/emulator/emulator -avd $(DEVICE) -dns-server 8.8.8.8 &

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
