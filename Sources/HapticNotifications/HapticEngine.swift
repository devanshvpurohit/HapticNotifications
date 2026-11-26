import AppKit
import AudioToolbox
import Combine
@preconcurrency import UserNotifications

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
    @Published var lastTriggerSource: String = "—"
    @Published var selectedPattern: HapticPattern = .doublePulse {
        didSet { UserDefaults.standard.set(selectedPattern.rawValue, forKey: "selectedPattern") }
    }
    @Published var intensity: Float = 0.9 {
        didSet { UserDefaults.standard.set(intensity, forKey: "intensity") }
    }
    @Published var playSystemSound: Bool = false {
        didSet { UserDefaults.standard.set(playSystemSound, forKey: "playSystemSound") }
    }
    @Published private(set) var motorConnected: Bool = false
    @Published private(set) var motorStatus: String = "Initializing..."
    @Published private(set) var notificationsAuthorized: Bool = false
    @Published private(set) var notificationStatus: String = "Checking..."

    private let actuator = MultitouchActuator()
    private var activeTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    private init() {
        if let savedPattern = UserDefaults.standard.string(forKey: "selectedPattern"),
           let pattern = HapticPattern(rawValue: savedPattern) {
            self.selectedPattern = pattern
        }
        if UserDefaults.standard.object(forKey: "intensity") != nil {
            self.intensity = UserDefaults.standard.float(forKey: "intensity")
        }
        self.playSystemSound = UserDefaults.standard.bool(forKey: "playSystemSound")

        connectMotor()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reconnectMotorOnWake()
            }
        }
    }

    private func reconnectMotorOnWake() {
        actuator.close()
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
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
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
    func recordNotification(source: String = "App") {
        notificationCount += 1
        lastTriggerSource = source
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
            // Short delay so a trackpad button click doesn't mask the first pulse
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            switch pattern {
            case .crispTap:
                actuator.play(tones: [(150, 1.0)], baseAmplitude: 0.0, ms: 220, level: level)

            case .doublePulse:
                actuator.play(tones: [(140, 1.0)], baseAmplitude: 0.0, ms: 320, level: level)
                try? await Task.sleep(nanoseconds: 420_000_000)
                guard !Task.isCancelled else { return }
                actuator.play(tones: [(180, 1.0)], baseAmplitude: 0.0, ms: 360, level: level)

            case .chime:
                actuator.play(tones: [(523.25, 0.7), (1046.5, 0.3)], baseAmplitude: 0.0, ms: 350, level: level)
                try? await Task.sleep(nanoseconds: 390_000_000)
                guard !Task.isCancelled else { return }
                actuator.play(tones: [(783.99, 0.7), (1567.98, 0.3)], baseAmplitude: 0.0, ms: 480, level: level)

            case .heartbeat:
                actuator.play(tones: [(110, 1.0)], baseAmplitude: 0.0, ms: 320, level: level)
                try? await Task.sleep(nanoseconds: 420_000_000)
                guard !Task.isCancelled else { return }
                actuator.play(tones: [(95, 1.0)], baseAmplitude: 0.0, ms: 420, level: level)

            case .urgentAlert:
                for i in 0..<3 {
                    guard !Task.isCancelled else { return }
                    actuator.play(tones: [(220, 0.5), (880, 0.5)], baseAmplitude: 0.0, ms: 300, level: level)
                    if i < 2 {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                }
            }
        }
    }

    /// Plays a custom single frequency tone on the trackpad motor (for testing/tuning).
    func playCustomTone(hz: Double, ms: Double = 500) {
        if !motorConnected {
            connectMotor()
        }
        guard motorConnected else {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
            return
        }
        let level = intensity
        activeTask?.cancel()
        activeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            actuator.play(tones: [(hz, 1.0)], baseAmplitude: 0.0, ms: ms, level: level)
        }
    }

    /// Static helper for convenience.
    static func notification() {
        shared.playPattern(shared.selectedPattern)
    }
}
