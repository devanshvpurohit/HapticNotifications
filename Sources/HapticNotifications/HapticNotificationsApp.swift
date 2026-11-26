import SwiftUI

@main
struct HapticNotificationsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Haptic Notifications", systemImage: "bell.badge.waveform.fill") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
