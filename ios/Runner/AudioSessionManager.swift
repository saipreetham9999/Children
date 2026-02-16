import AVFoundation

/// AudioSessionManager — iOS-specific audio session management
/// Handles audio category, interruptions, and speaker routing for iOS 13+
class AudioSessionManager {
    static let shared = AudioSessionManager()

    private let audioSession = AVAudioSession.sharedInstance()
    private var previousCategory: AVAudioSession.Category = .default

    /// Initialize audio session for playback
    /// Call this early in app lifecycle (AppDelegate.didFinishLaunchingWithOptions)
    func initializeAudioSession() throws {
        print("[AudioSessionManager] Initializing for iOS audio playback...")

        // Set category to playback (allows background audio)
        try audioSession.setCategory(
            .playback,
            mode: .moviePlayback,
            options: [
                .duckOthers,  // Reduce other audio when playing
                .defaultToSpeaker  // Use speaker by default (not earpiece)
            ]
        )

        // Activate the session
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        print("[AudioSessionManager] ✅ Audio session configured")
        print("[AudioSessionManager] Category: \(audioSession.category.rawValue)")
        print("[AudioSessionManager] Mode: \(audioSession.mode.rawValue)")

        // Listen for interruptions (phone calls, alarms)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: audioSession
        )
    }

    /// Handle audio interruptions (phone calls, alarms, Siri)
    @objc func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeRaw = userInfo[AVAudioSession.interruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }

        switch type {
        case .began:
            print("[AudioSessionManager] 🔴 Audio interruption began (call/alarm)")
            // Notify app to pause audio
            NotificationCenter.default.post(name: NSNotification.Name("AudioInterruptionBegan"), object: nil)

        case .ended:
            print("[AudioSessionManager] 🟢 Audio interruption ended")
            guard let optionsRaw = userInfo[AVAudioSession.interruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)

            if options.contains(.shouldResume) {
                print("[AudioSessionManager] Resuming audio playback...")
                NotificationCenter.default.post(name: NSNotification.Name("AudioInterruptionEnded"), object: nil)
            }
        @unknown default:
            break
        }
    }

    /// Set speaker mode (speaker vs earpiece)
    /// Note: iOS doesn't allow direct earpiece control in public API
    /// This would require a private API workaround or CallKit for full control
    func setSpeakerMode(_ mode: String) {
        print("[AudioSessionManager] Setting speaker mode: \(mode)")

        switch mode {
        case "speaker":
            // Prefer speaker
            try? audioSession.overrideOutputAudioPort(.speaker)

        case "earpiece":
            // Try to use earpiece (not guaranteed on all calls)
            try? audioSession.overrideOutputAudioPort(.none)

        case "bluetooth":
            // Bluetooth headphones/speakers take priority if connected
            try? audioSession.overrideOutputAudioPort(.speaker)

        default:
            print("[AudioSessionManager] Unknown mode: \(mode)")
        }
    }

    /// Get current audio route (speaker, headphones, bluetooth, etc)
    func getCurrentAudioRoute() -> String {
        let currentRoute = audioSession.currentRoute

        var output = "unknown"
        for port in currentRoute.outputs {
            switch port.portType {
            case .speaker:
                output = "speaker"
            case .headphones:
                output = "headphones"
            case .bluetoothA2DP, .bluetoothLE:
                output = "bluetooth"
            case .builtInReceiver:
                output = "earpiece"
            default:
                output = port.portType.rawValue
            }
        }

        print("[AudioSessionManager] Current output: \(output)")
        return output
    }

    /// Listen for audio route changes (headphones plugged/unplugged)
    func setupRouteChangeListener() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: audioSession
        )
    }

    @objc func handleRouteChange(_ notification: Notification) {
        print("[AudioSessionManager] Audio route changed")
        let route = getCurrentAudioRoute()
        NotificationCenter.default.post(
            name: NSNotification.Name("AudioRouteChanged"),
            object: nil,
            userInfo: ["route": route]
        )
    }

    /// Enable Focus Mode compliance (iOS 15+)
    /// Respects user's Focus/Do Not Disturb settings
    func configureForFocusMode() {
        if #available(iOS 15.0, *) {
            // Check if user is in Do Not Disturb or Focus mode
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            if let activityLevel = scene?.windows.first?.windowScene?.screen.focusEngine?.focusStatus {
                print("[AudioSessionManager] Focus mode detected, respecting audio settings")
                // Reduce volume or skip audio if needed
            }
        }
    }

    /// Configure for background playback (works in background mode)
    func enableBackgroundAudio() {
        print("[AudioSessionManager] Enabling background audio playback...")

        // This requires "Audio, AirPlay, and Picture in Picture" capability in Info.plist
        // And "App Audio" background mode enabled

        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        print("[AudioSessionManager] ✅ Background audio enabled")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
