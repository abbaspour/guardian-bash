import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    NSApp.registerForRemoteNotifications()
                    print("Registration requested...")
                    fflush(stdout)
                }
            } else {
                print("Permission denied: \(String(describing: error))")
                fflush(stdout)
            }
        }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("\n--- DEVICE TOKEN ---")
        print(token)
        print("--------------------\n")
        fflush(stdout)
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register: \(error)")
        fflush(stdout)
    }

    // Primary handler — fires whenever the app is running, foreground or background
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        print("\n=== GUARDIAN PUSH NOTIFICATION ===")
        printPayload(userInfo)
    }

    // Fires when notification arrives and app is frontmost
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 willPresent notification: UNNotification,
                                 withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let content = notification.request.content
        print("\n=== GUARDIAN PUSH NOTIFICATION ===")
        if !content.title.isEmpty    { print("title:    \(content.title)") }
        if !content.subtitle.isEmpty { print("subtitle: \(content.subtitle)") }
        if !content.body.isEmpty     { print("body:     \(content.body)") }
        printPayload(content.userInfo)
        completionHandler([.banner, .sound])
    }

    // Fires when user clicks the notification banner
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 didReceive response: UNNotificationResponse,
                                 withCompletionHandler completionHandler: @escaping () -> Void) {
        print("\n=== GUARDIAN PUSH NOTIFICATION (user tapped) ===")
        printPayload(response.notification.request.content.userInfo)
        completionHandler()
    }

    private func printPayload(_ userInfo: [AnyHashable: Any]) {
        print("--- payload ---")
        for (key, value) in userInfo {
            print("  \(key): \(value)")
        }
        print("---------------")
        fflush(stdout)
    }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
