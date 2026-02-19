# Guardian Push
This project is a set of bash scripts that interact with Auth0 Guardian API.

- enroll/unenroll a device to Guardian push notifications
- Receives push notifications from Guardian
- Resolves (accept/reject) transaction from Guardian

# Boostrap
`tf/` folder contains Terraform scripts to deploy AWS SNS and Auth0 resources.

# Guardian Push Notification App
There is a minimal Android app in `android/` folder that receives push notifications from Guardian.

1. Copy your google-services.json to android/app/
2. Open in Android Studio or build from command line:
    ```shell
   cd android
   gradle wrapper   # generates gradle-wrapper.jar
   ./gradlew assembleDebug
   ```
3. Install Android SDK command-line tools. Go to Android Studio > Tools > SDK Tools and select command-line tools. 
   ![Android Studio CLI Installation](./img/android-studio-cli.png)
4. Install on the device and launch the app.
   ```shell
   make list-devices  # update DEVICE in Makefile to match 
   make boot
   ```
5. Get your FCM token from:
   - The app UI (tap "Copy Token"), or
   - Logcat: `adb logcat -s GuardianFCM`
6. Use the token with enrollment:
    ```shell
   ./enroll-device.sh -g <fcm-token> ...
   ```
7. When Guardian sends a push, check logcat for:
   D/GuardianFCM: === GUARDIAN PUSH NOTIFICATION ===
   D/GuardianFCM: challenge: <value>
   D/GuardianFCM: txtkn: <value>