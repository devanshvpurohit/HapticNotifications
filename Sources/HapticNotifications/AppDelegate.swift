import Cocoa
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Bundle.main.bundleIdentifier != nil else {
            print("⚠️ Warning: Running as unbundled binary. UNUserNotificationCenter requires an .app bundle with Info.plist.")
            return
        }

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        Task {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    print("Notification permission granted")
                } else {
                    print("Notification permission not granted")
                }
            } catch {
                print("Notification authorization error: \(error)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HapticEngine.shared.shutdown()
    }

    // Called when a notification arrives while the app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            HapticEngine.shared.recordNotification()
        }
        completionHandler([.banner, .sound])
    }

    // Called when user interacts with a notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            HapticEngine.shared.recordNotification()
        }
        completionHandler()
    }
}
