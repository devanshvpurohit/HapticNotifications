import Foundation

/// Low-level wrapper around macOS private MultitouchSupport.framework
/// (based on os6/nospeaker's trackpad motor driver).
/// Drives the Force Touch trackpad actuator directly with custom waveforms and frequencies.
final class MultitouchActuator: @unchecked Sendable {
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias GetID = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    private typealias IsBuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
    private typealias ActuatorCreate = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias ActuatorOpen = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuatorClose = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuationCreate = @convention(c) (CFDictionary, Int32) -> UnsafeMutableRawPointer?
    private typealias ActuationPlay = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer, UInt32, Float, Float) -> Int32

    private let framework: UnsafeMutableRawPointer?
    private let createList: CreateList?
    private let getID: GetID?
    private let isBuiltInFn: IsBuiltIn?
    private let actuatorCreate: ActuatorCreate?
    private let actuatorOpen: ActuatorOpen?
    private let actuatorClose: ActuatorClose?
    private let actuationCreate: ActuationCreate?
    private let actuationPlay: ActuationPlay?

    private var motorRef: CFTypeRef?
    private var motorPointer: UnsafeMutableRawPointer?

    private(set) var deviceID: UInt64 = 0
    private(set) var isBuiltIn: Bool = false
    private(set) var isOpen: Bool = false

    var isSupported: Bool {
        createList != nil && getID != nil && actuatorCreate != nil &&
        actuatorOpen != nil && actuationCreate != nil && actuationPlay != nil
    }

    init() {
        let mt = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
        self.framework = mt

        func sym<T>(_ name: String, _: T.Type) -> T? {
            guard let mt, let p = dlsym(mt, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }

        self.createList = sym("MTDeviceCreateList", CreateList.self)
        self.getID = sym("MTDeviceGetDeviceID", GetID.self)
        self.isBuiltInFn = sym("MTDeviceIsBuiltIn", IsBuiltIn.self)
        self.actuatorCreate = sym("MTActuatorCreateFromDeviceID", ActuatorCreate.self)
        self.actuatorOpen = sym("MTActuatorOpen", ActuatorOpen.self)
        self.actuatorClose = sym("MTActuatorClose", ActuatorClose.self)
        self.actuationCreate = sym("MTActuationCreateFromDictionary", ActuationCreate.self)
        self.actuationPlay = sym("MTActuationActuate", ActuationPlay.self)
    }

    deinit {
        close()
    }

    @discardableResult
    func open(preferExternal: Bool = false) -> Bool {
        if isOpen { return true }
        guard let createList, let getID, let actuatorCreate, let actuatorOpen,
              actuationCreate != nil, actuationPlay != nil else {
            return false
        }

        guard let list = createList()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else {
            return false
        }

        var devices: [(id: UInt64, builtIn: Bool)] = []
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            var id: UInt64 = 0
            if getID(dev, &id) == 0 {
                devices.append((id, isBuiltInFn?(dev) ?? false))
            }
        }

        let candidates: [(id: UInt64, builtIn: Bool)]
        if preferExternal {
            candidates = devices.filter { !$0.builtIn }
        } else {
            candidates = devices.sorted { $0.builtIn && !$1.builtIn }
        }

        for candidate in candidates {
            if let ref = actuatorCreate(candidate.id)?.takeRetainedValue(), actuatorOpen(ref) == 0 {
                self.motorRef = ref
                self.motorPointer = Unmanaged.passUnretained(ref).toOpaque()
                self.deviceID = candidate.id
                self.isBuiltIn = candidate.builtIn
                self.isOpen = true
                return true
            }
        }

        return false
    }

    func close() {
        if let ref = motorRef, let actuatorClose {
            _ = actuatorClose(ref)
        }
        motorRef = nil
        motorPointer = nil
        isOpen = false
    }

    /// Plays a custom waveform on the Force Touch motor.
    /// - Parameters:
    ///   - tones: List of (frequency in Hz, relative amplitude) pairs.
    ///   - baseAmplitude: Gaussian base click amplitude (0.0 to 1.0).
    ///   - ms: Duration in milliseconds.
    ///   - level: Overall actuation strength (0.0 to 1.0).
    func play(tones: [(hz: Double, amp: Double)], baseAmplitude: Double = 0.0, ms: Double, level: Float = 1.0) {
        if !isOpen {
            _ = open()
        }
        guard let motorPointer, let actuationCreate, let actuationPlay else { return }

        let sum = max(tones.reduce(0) { $0 + $1.amp }, 0.0001)
        let toneDicts: [[String: Any]] = tones.map {
            [
                "Type": "Sine",
                "Amplitude": $0.amp / sum,
                "DurationMS": ms,
                "DelayMS": 0.0,
                "FrequencykHz": $0.hz / 1000.0
            ]
        }

        var shape: [String: Any] = [
            "BaseWaveform": [
                "Type": "Gaussian",
                "Amplitude": min(1.0, max(0.0, baseAmplitude)),
                "DurationMS": ms
            ]
        ]
        if !toneDicts.isEmpty {
            shape["Tones"] = toneDicts
        }

        guard let act = actuationCreate(shape as CFDictionary, 0) else { return }
        _ = actuationPlay(act, motorPointer, 0, min(1.0, max(0.0, level)), 0)
        Unmanaged<AnyObject>.fromOpaque(act).release()
    }
}
