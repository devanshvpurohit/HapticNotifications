import SwiftUI

@main
struct HapticNotificationsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Haptic Notifications", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Haptic Notifications", systemImage: "bell.badge.waveform.fill") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
