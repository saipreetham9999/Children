import Flutter

/// Platform channel for audio session management
/// Allows Dart code to control iOS audio session settings
class AudioSessionChannel: NSObject {
    static let channelName = "com.sharogai.audio/session"

    static func register(with registrar: FlutterPluginRegistry) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger() as! FlutterBinaryMessenger
        )

        channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
            switch call.method {
            case "initializeAudioSession":
                do {
                    try AudioSessionManager.shared.initializeAudioSession()
                    result(["status": "success"])
                } catch {
                    result(FlutterError(
                        code: "AUDIO_SESSION_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }

            case "setSpeakerMode":
                let mode = call.arguments as? String ?? "speaker"
                AudioSessionManager.shared.setSpeakerMode(mode)
                result(["status": "success", "mode": mode])

            case "getCurrentRoute":
                let route = AudioSessionManager.shared.getCurrentAudioRoute()
                result(["route": route])

            case "setupRouteChangeListener":
                AudioSessionManager.shared.setupRouteChangeListener()
                result(["status": "success"])

            case "enableBackgroundAudio":
                AudioSessionManager.shared.enableBackgroundAudio()
                result(["status": "success"])

            case "configureFocusMode":
                AudioSessionManager.shared.configureForFocusMode()
                result(["status": "success"])

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
