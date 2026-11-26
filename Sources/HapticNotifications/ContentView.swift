import SwiftUI
import UserNotifications

struct ContentView: View {
    @ObservedObject private var engine = HapticEngine.shared
    @State private var scheduledNotificationText: String? = nil
    @State private var customHz: Double = 440

    var body: some View {
        VStack(spacing: 16) {
            // Header & Motor Status
            VStack(spacing: 6) {
                Text("Haptic Notifications")
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 6) {
                    Circle()
                        .fill(engine.motorConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(engine.motorStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(engine.notificationsAuthorized ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(engine.notificationStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !engine.notificationsAuthorized {
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                }
            }

            // Notification Counter Card
            HStack(spacing: 16) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications Received")
                        .font(.headline)
                    Text("\(engine.notificationCount)")
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        .foregroundColor(engine.notificationCount > 0 ? .green : .primary)
                }

                Spacer()
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)

            // Pattern & Settings Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Haptic Pattern")
                        .font(.headline)
                    Spacer()
                    Picker("", selection: $engine.selectedPattern) {
                        ForEach(HapticPattern.allCases) { pattern in
                            Text(pattern.rawValue).tag(pattern)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                Text(engine.selectedPattern.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Intensity")
                        .font(.subheadline)
                    Slider(value: $engine.intensity, in: 0.2...1.0, step: 0.05)
                    Text("\(Int(engine.intensity * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 38, alignment: .trailing)
                }

                Toggle("Also play Mac speaker alert sound", isOn: $engine.playSystemSound)
                    .font(.subheadline)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)

            // Custom Frequency Tester (powered by MultitouchSupport)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Trackpad Tone Test")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(Int(customHz)) Hz")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 10) {
                    Slider(value: $customHz, in: 100...2000, step: 10)
                    Button("Play Tone") {
                        engine.playCustomTone(hz: customHz, ms: 120)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)

            if let text = scheduledNotificationText {
                Text(text)
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            // Action Buttons
            HStack(spacing: 10) {
                Button(action: {
                    engine.recordNotification()
                }) {
                    Label("Trigger Pattern", systemImage: "hand.tap.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)

                Button(action: {
                    scheduleTestNotification()
                }) {
                    Label("Test Notification (3s)", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func scheduleTestNotification() {
        guard Bundle.main.bundleIdentifier != nil else {
            self.scheduledNotificationText = "⚠️ UNUserNotificationCenter requires running inside HapticNotifications.app"
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Haptic Notification Test"
        content.body = "Trackpad haptic pattern: \(engine.selectedPattern.rawValue)"
        content.sound = engine.playSystemSound ? .default : nil

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.scheduledNotificationText = "Failed to schedule: \(error.localizedDescription)"
                } else {
                    self.scheduledNotificationText = "Notification scheduled in 3 seconds..."
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
