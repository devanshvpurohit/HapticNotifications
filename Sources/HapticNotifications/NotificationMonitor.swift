import AppKit
import ApplicationServices
import Combine

/// Watches macOS NotificationCenter (`com.apple.notificationcenterui`) via Accessibility
/// so incoming notifications from any app trigger trackpad haptics 24/7.
@MainActor
final class NotificationMonitor: ObservableObject {
    static let shared = NotificationMonitor()

    @Published private(set) var isAccessibilityGranted: Bool = AXIsProcessTrusted()
    @Published private(set) var isWatching: Bool = false
    @Published var isEnabled: Bool = true {
        didSet {
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }

    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var lastTriggerTime: Date = .distantPast
    private var pollTask: Task<Void, Never>?
    private var launchObserver: NSObjectProtocol?

    private init() {
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            if bundleID == "com.apple.notificationcenterui" {
                Task { @MainActor in
                    self?.attachObserverIfPossible()
                }
            }
        }
    }

    func start() {
        refreshStatus()
        guard isEnabled else { return }

        if isAccessibilityGranted {
            attachObserverIfPossible()
        } else {
            startPermissionPolling()
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        detachObserver()
    }

    func refreshStatus() {
        isAccessibilityGranted = AXIsProcessTrusted()
        if isAccessibilityGranted && isEnabled && !isWatching {
            attachObserverIfPossible()
        } else if !isAccessibilityGranted {
            detachObserver()
        }
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        startPermissionPolling()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPermissionPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, !Task.isCancelled else { return }
                let trusted = AXIsProcessTrusted()
                self.isAccessibilityGranted = trusted
                if trusted {
                    if self.isEnabled {
                        self.attachObserverIfPossible()
                    }
                    return
                }
            }
        }
    }

    private func attachObserverIfPossible() {
        guard isEnabled, AXIsProcessTrusted() else { return }
        guard let ncApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else {
            return
        }

        let pid = ncApp.processIdentifier
        if isWatching && observedPID == pid { return }

        detachObserver()

        var newObserver: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let monitor = Unmanaged<NotificationMonitor>.fromOpaque(refcon).takeUnretainedValue()
            let notifName = notification as String
            var roleRef: CFTypeRef?
            var subroleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
            let role = (roleRef as? String) ?? ""
            let subrole = (subroleRef as? String) ?? ""
            Task { @MainActor in
                monitor.handleAXEvent(name: notifName, role: role, subrole: subrole)
            }
        }

        guard AXObserverCreate(pid, callback, &newObserver) == .success, let newObserver else {
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let events: [String] = [
            kAXWindowCreatedNotification as String,
            kAXCreatedNotification as String,
            kAXLayoutChangedNotification as String
        ]

        var attachedAny = false
        for event in events {
            let res = AXObserverAddNotification(newObserver, appElement, event as CFString, selfPtr)
            if res == .success {
                attachedAny = true
            }
        }

        if attachedAny {
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
            self.observer = newObserver
            self.observedPID = pid
            self.isWatching = true
        }
    }

    private func detachObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = 0
        isWatching = false
    }

    private func handleAXEvent(name: String, role: String, subrole: String) {
        guard isEnabled else { return }

        // Only trigger for actual banner/window creations or layout changes with notification elements
        if name == (kAXLayoutChangedNotification as String) {
            guard observedPID != 0 else { return }
            let appElement = AXUIElementCreateApplication(observedPID)
            var windowsRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
            let windows = (windowsRef as? [AnyObject]) ?? []
            guard err == .success, !windows.isEmpty else { return }
        } else if name == (kAXCreatedNotification as String) {
            let isBanner = role == (kAXWindowRole as String) ||
                           subrole.localizedCaseInsensitiveContains("Banner") ||
                           subrole.localizedCaseInsensitiveContains("Alert") ||
                           subrole.localizedCaseInsensitiveContains("Notification")
            guard isBanner else { return }
        }

        let now = Date()
        // Debounce multiple AX events for the same notification banner
        guard now.timeIntervalSince(lastTriggerTime) >= 1.0 else { return }
        lastTriggerTime = now
        HapticEngine.shared.recordNotification(source: "macOS Notification")
    }
}
