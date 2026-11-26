import AppKit
import AudioToolbox
import Combine
import UserNotifications

/// Haptic notification patterns driven directly on the Force Touch trackpad motor.
enum HapticPattern: String, CaseIterable, Identifiable {
    case doublePulse = "Double Pulse"
    case chime = "Trackpad Chime"
    case crispTap = "Crisp Tap"
    case heartbeat = "Heartbeat"
    case urgentAlert = "Urgent Alert"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .doublePulse: return "Two crisp physical taps (160 Hz)"
        case .chime: return "Two-note glass chime (523 → 784 Hz, audible even muted)"
        case .crispTap: return "Single sharp tactile click (180 Hz)"
        case .heartbeat: return "Deep lub-dub thump (120 → 100 Hz)"
        case .urgentAlert: return "Three rapid resonant pulses (880 Hz)"
        }
    }
}

/// HapticEngine drives the Force Touch trackpad actuator using os6/nospeaker's MultitouchSupport engine,
/// falling back to AppKit's NSHapticFeedbackManager when unavailable.
@MainActor
final class HapticEngine: ObservableObject {
    static let shared = HapticEngine()

    @Published var notificationCount: Int = 0
    @Published var selectedPattern: HapticPattern = .doublePulse
    @Published var intensity: Float = 0.9
    @Published var playSystemSound: Bool = false
    @Published private(set) var motorConnected: Bool = false
    @Published private(set) var motorStatus: String = "Initializing..."
    @Published private(set) var notificationsAuthorized: Bool = false
    @Published private(set) var notificationStatus: String = "Checking..."

    private let actuator = MultitouchActuator()
    private var activeTask: Task<Void, Never>?

    private init() {
        connectMotor()
    }

    func connectMotor(preferExternal: Bool = false) {
        if actuator.open(preferExternal: preferExternal) {
            motorConnected = true
            let kind = actuator.isBuiltIn ? "Built-in Force Touch Trackpad" : "External Magic Trackpad"
            motorStatus = "\(kind) (MultitouchSupport active)"
        } else {
            motorConnected = false
            motorStatus = "Fallback mode (NSHapticFeedbackManager)"
        }
    }

    func shutdown() {
        activeTask?.cancel()
        actuator.close()
        motorConnected = false
    }

    func refreshNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else {
            notificationsAuthorized = false
            notificationStatus = "Unbundled binary (run .app)"
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                switch status {
                case .authorized, .provisional:
                    self.notificationsAuthorized = true
                    self.notificationStatus = "Notifications Allowed"
                case .denied:
                    self.notificationsAuthorized = false
                    self.notificationStatus = "Notifications Denied (enable in System Settings)"
                case .notDetermined:
                    self.notificationsAuthorized = false
                    self.notificationStatus = "Permission Not Requested"
                @unknown default:
                    self.notificationsAuthorized = false
                    self.notificationStatus = "Unknown Permission State"
                }
            }
        }
    }

    func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                self.notificationsAuthorized = granted
                self.notificationStatus = granted ? "Notifications Allowed" : "Notifications Denied (enable in System Settings)"
            } catch {
                self.notificationsAuthorized = false
                self.notificationStatus = "Error: \(error.localizedDescription)"
            }
        }
    }

    /// Increments notification count and plays the selected haptic pattern.
    func recordNotification() {
        notificationCount += 1
        playPattern(selectedPattern)
    }

    /// Plays a specific haptic pattern on the trackpad motor.
    func playPattern(_ pattern: HapticPattern) {
        activeTask?.cancel()

        if playSystemSound {
            AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_UserPreferredAlert))
        }

        if !motorConnected {
            connectMotor()
        }

        guard motorConnected else {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
            return
        }

        let level = intensity
        activeTask = Task { @MainActor in
            switch pattern {
            case .crispTap:
                actuator.play(tones: [(180, 1.0)], baseAmplitude: 0.9, ms: 25, level: level)

            case .doublePulse:
                actuator.play(tones: [(160, 1.0)], baseAmplitude: 0.85, ms: 28, level: level)
                try? await Task.sleep(nanoseconds: 95_000_000)
                guard !Task.isCancelled else { return }
                actuator.play(tones: [(200, 1.0)], baseAmplitude: 0.9, ms: 28, level: level)

            case .chime:
                actuator.play(tones: [(523.25, 0.7), (1046.5, 0.3)], baseAmplitude: 0.25, ms: 90, level: level)
                try? await Task.sleep(nanoseconds: 105_000_000)
                guard !Task.isCancelled else { return }
                actuator.play(tones: [(783.99, 0.7), (1567.98, 0.3)], baseAmplitude: 0.25, ms: 130, level: level)

            case .heartbeat:
                actuator.play(tones: [(120, 1.0)], baseAmplitude: 0.8, ms: 40, level: level)
                try? await Task.sleep(nanoseconds: 130_000_000)
                guard !Task.isCancelled else { return }
                actuator.play(tones: [(100, 1.0)], baseAmplitude: 0.65, ms: 55, level: level * 0.85)

            case .urgentAlert:
                for i in 0..<3 {
                    guard !Task.isCancelled else { return }
                    actuator.play(tones: [(880, 0.6), (440, 0.4)], baseAmplitude: 0.6, ms: 55, level: level)
                    if i < 2 {
                        try? await Task.sleep(nanoseconds: 110_000_000)
                    }
                }
            }
        }
    }

    /// Plays a custom single frequency tone on the trackpad motor (for testing/tuning).
    func playCustomTone(hz: Double, ms: Double = 80) {
        if !motorConnected {
            connectMotor()
        }
        guard motorConnected else {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
            return
        }
        actuator.play(tones: [(hz, 1.0)], baseAmplitude: 0.2, ms: ms, level: intensity)
    }

    /// Static helper for convenience.
    static func notification() {
        shared.playPattern(shared.selectedPattern)
    }
}
