import Foundation
import UIKit
import AVFoundation

/// MediaPlaybackBridge — iOS native media playback support
/// Handles Now Playing info, remote control events, audio session for media
@objc class MediaPlaybackBridge: NSObject {

    static let shared = MediaPlaybackBridge()

    private var isConfigured = false

    private override init() {
        super.init()
    }

    /// Register platform channel
    static func registerWithController(_ controller: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: "com.sharogai.media/playback",
            binaryMessenger: controller.binaryMessenger
        )

        channel.setMethodCallHandler { (call, result) in
            shared.handleMethodCall(call, result: result)
        }
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "configureAudioSession":
            configureAudioSession(result: result)

        case "setNowPlaying":
            if let args = call.arguments as? [String: Any] {
                setNowPlaying(args: args, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
            }

        case "enableRemoteCommands":
            enableRemoteCommands(result: result)

        case "setVolume":
            if let args = call.arguments as? [String: Any],
               let volume = args["volume"] as? Double {
                setSystemVolume(volume: Float(volume), result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
            }

        case "getAudioSessionInfo":
            getAudioSessionInfo(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Audio Session

    private func configureAudioSession(result: @escaping FlutterResult) {
        let session = AVAudioSession.sharedInstance()

        do {
            // Configure for media playback with Bluetooth support
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
            )
            try session.setActive(true)
            isConfigured = true

            // Monitor interruptions (calls, alarms)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInterruption),
                name: AVAudioSession.interruptionNotification,
                object: session
            )

            // Monitor route changes (headphones, Bluetooth)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRouteChange),
                name: AVAudioSession.routeChangeNotification,
                object: session
            )

            result(["success": true, "category": "playback"])
        } catch {
            result(FlutterError(
                code: "AUDIO_SESSION_ERROR",
                message: error.localizedDescription,
                details: nil
            ))
        }
    }

    // MARK: - Now Playing

    private func setNowPlaying(args: [String: Any], result: @escaping FlutterResult) {
        var info = [String: Any]()

        if let title = args["title"] as? String {
            info[MPMediaItemPropertyTitle] = title
        }
        if let artist = args["artist"] as? String {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let duration = args["duration"] as? Double {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let position = args["position"] as? Double {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = args["isPlaying"] as? Bool == true ? 1.0 : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        result(["success": true])
    }

    // MARK: - Remote Commands

    private func enableRemoteCommands(result: @escaping FlutterResult) {
        let center = MPRemoteCommandCenter.shared()

        // Play
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { _ in
            // Send to Flutter via method channel
            return .success
        }

        // Pause
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { _ in
            return .success
        }

        // Next/Previous (for playlist)
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true

        // Volume (handled by system)

        result(["success": true, "commands_enabled": true])
    }

    // MARK: - Volume

    private func setSystemVolume(volume: Float, result: @escaping FlutterResult) {
        // Volume is controlled via MPVolumeView in Flutter UI
        // This just reports the request
        result(["success": true, "requested_volume": volume])
    }

    // MARK: - Audio Info

    private func getAudioSessionInfo(result: @escaping FlutterResult) {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute

        var outputs: [[String: Any]] = []
        for output in route.outputs {
            outputs.append([
                "name": output.portName,
                "type": output.portType.rawValue,
                "uid": output.uid
            ])
        }

        result([
            "category": session.category.rawValue,
            "mode": session.mode.rawValue,
            "is_active": isConfigured,
            "output_volume": session.outputVolume,
            "outputs": outputs,
            "sample_rate": session.sampleRate,
            "is_other_audio_playing": session.isOtherAudioPlaying
        ])
    }

    // MARK: - Interruption Handling

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            print("[MediaBridge] Audio interrupted (call/alarm)")
        case .ended:
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    print("[MediaBridge] Audio interruption ended, should resume")
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Route Change

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .newDeviceAvailable:
            print("[MediaBridge] New audio device connected")
        case .oldDeviceUnavailable:
            print("[MediaBridge] Audio device disconnected")
        default:
            break
        }
    }
}
