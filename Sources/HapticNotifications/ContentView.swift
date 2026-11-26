import SwiftUI
import UserNotifications

struct ContentView: View {
    @ObservedObject private var engine = HapticEngine.shared
    @ObservedObject private var monitor = NotificationMonitor.shared
    @State private var scheduledNotificationText: String? = nil
    @State private var customHz: Double = 180

    var body: some View {
        VStack(spacing: 14) {
            // Header & Status
            VStack(spacing: 5) {
                HStack {
                    Text("Haptic Notifications")
                        .font(.headline)
                        .fontWeight(.bold)
                    Spacer()
                    Text("24/7 Menu Bar")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(engine.motorConnected ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(engine.motorStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(monitor.isWatching ? Color.green : (monitor.isAccessibilityGranted ? Color.yellow : Color.orange))
                        .frame(width: 7, height: 7)
                    if monitor.isWatching {
                        Text("Watching all Mac notifications")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if monitor.isAccessibilityGranted {
                        Text("Accessibility granted (paused)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Needs Accessibility to watch all apps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Allow") {
                            monitor.requestAccessibilityPermission()
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    }
                    Spacer()
                }
            }

            // Counter & System-wide Toggle
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications Triggered")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Last: \(engine.lastTriggerSource)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text("\(engine.notificationCount)")
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .foregroundColor(engine.notificationCount > 0 ? .green : .primary)
                }

                Toggle("Vibrate on all Mac notifications", isOn: $monitor.isEnabled)
                    .font(.subheadline)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Pattern & Settings Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Pattern")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Picker("", selection: $engine.selectedPattern) {
                        ForEach(HapticPattern.allCases) { pattern in
                            Text(pattern.rawValue).tag(pattern)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 165)
                }

                Text(engine.selectedPattern.subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Intensity")
                        .font(.caption)
                    Slider(value: $engine.intensity, in: 0.2...1.0, step: 0.05)
                    Text("\(Int(engine.intensity * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 34, alignment: .trailing)
                }

                Toggle("Also play Mac speaker alert sound", isOn: $engine.playSystemSound)
                    .font(.caption)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Custom Frequency Tester
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Trackpad Tone Test")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(Int(customHz)) Hz")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    Slider(value: $customHz, in: 100...2000, step: 10)
                    Button("Play Tone") {
                        engine.playCustomTone(hz: customHz, ms: 500)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            if let text = scheduledNotificationText {
                Text(text)
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            // Action Buttons
            HStack(spacing: 8) {
                Button(action: {
                    engine.recordNotification(source: "Manual Test")
                }) {
                    Label("Trigger Pattern", systemImage: "hand.tap.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: {
                    scheduleTestNotification()
                }) {
                    Label("Test Banner (3s)", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            HStack {
                if !monitor.isAccessibilityGranted {
                    Button("Accessibility Settings") {
                        monitor.openAccessibilitySettings()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(width: 370)
    }

    private func scheduleTestNotification() {
        guard Bundle.main.bundleIdentifier != nil else {
            self.scheduledNotificationText = "⚠️ Requires running inside HapticNotifications.app"
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Haptic Notification Test"
        content.body = "Trackpad haptic pattern: \(engine.selectedPattern.rawValue)"
        content.sound = engine.playSystemSound ? .default : nil

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                self.scheduledNotificationText = "Notification scheduled in 3 seconds..."
            } catch {
                self.scheduledNotificationText = "Failed: \(error.localizedDescription)"
            }
        }
    }
}
