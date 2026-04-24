import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // 1. Request permission
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    NSApp.registerForRemoteNotifications()
                    print("Registration requested...")
                }
            } else {
                print("Permission denied: \(String(describing: error))")
            }
        }
    }

    // 2. Print the Device Token (You need this to send pushes)
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("\n--- DEVICE TOKEN ---")
        print(token)
        print("--------------------\n")
    }

    // 3. Handle incoming notification while app is running
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("Received Notification: \(notification.request.content.userInfo)")
        completionHandler([.banner, .sound])
    }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()