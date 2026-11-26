# HapticNotifications

A macOS SwiftUI application that drives the Force Touch trackpad haptic motor directly for notifications and custom haptic feedback—even when your Mac is muted.

Built on top of [`os6/nospeaker`](https://github.com/os6/nospeaker)'s `MultitouchSupport` trackpad motor driver.

## Features

- **Direct Force Touch Motor Control**: Uses `MultitouchSupport.framework` (`MTActuationCreateFromDictionary` / `MTActuationActuate`) to play custom waveforms, frequencies (`100–2000 Hz`), and intensities directly on the trackpad actuator, with automatic fallback to `NSHapticFeedbackManager`.
- **Custom Haptic Patterns**:
  - **Double Pulse** — Two crisp physical taps (`160 Hz → 200 Hz`)
  - **Trackpad Chime** — Two-note glass chime (`523 Hz → 784 Hz`, audible from the trackpad even when muted)
  - **Crisp Tap** — Single sharp tactile click (`180 Hz`)
  - **Heartbeat** — Deep lub-dub thump (`120 Hz → 100 Hz`)
  - **Urgent Alert** — Three rapid resonant pulses (`880 Hz + 440 Hz`)
- **Notification Integration**: Triggers haptics on incoming notifications via `UNUserNotificationCenterDelegate` with a built-in 3-second test notification trigger.
- **Launch at Login**: Includes scripts to install to `~/Applications` and register with macOS Login Items.

## Requirements

- macOS 12.0 or later
- MacBook (2015 or later) with Force Touch trackpad or Magic Trackpad 2+
- Swift / Xcode Command Line Tools

## Usage

```sh
# Build, package into HapticNotifications.app, and launch
./run.sh --open

# Install to ~/Applications and enable Launch at Login
./install-startup.sh

# Remove from macOS Login Items
./uninstall-startup.sh
```

## Credits

- Trackpad motor driver (`MultitouchSupport` FFI) adapted from [`os6/nospeaker`](https://github.com/os6/nospeaker) by Cody Collier.
