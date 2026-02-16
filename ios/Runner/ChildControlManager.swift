import Foundation
import UIKit

/// ChildControlManager — Native iOS child device controls
/// Bridges to Dart via platform channels for Screen Time, restrictions, etc.
@objc class ChildControlManager: NSObject {

    static let shared = ChildControlManager()

    // Settings storage
    private var screenTimeLimit: Int = 120 // minutes
    private var usedScreenTime: Int = 0
    private var contentFilterLevel: String = "moderate"
    private var bedtimeEnabled: Bool = false
    private var bedtimeStart: String = "21:00"
    private var bedtimeEnd: String = "07:00"
    private var blockedApps: [String] = []
    private var webFilterEnabled: Bool = false
    private var blockedWebsites: [String] = []
    private var locationSharingEnabled: Bool = false

    private override init() {
        super.init()
    }

    /// Register platform channel with Flutter engine
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.sharogai.child/control",
            binaryMessenger: registrar.messenger()
        )

        channel.setMethodCallHandler { (call, result) in
            shared.handleMethodCall(call, result: result)
        }
    }

    /// Register with FlutterViewController directly
    static func registerWithController(_ controller: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: "com.sharogai.child/control",
            binaryMessenger: controller.binaryMessenger
        )

        channel.setMethodCallHandler { (call, result) in
            shared.handleMethodCall(call, result: result)
        }
    }

    /// Handle method calls from Dart
    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "requestAuthorization":
            requestAuthorization(result: result)

        case "setScreenTimeLimit":
            if let args = call.arguments as? [String: Any],
               let minutes = args["minutes"] as? Int {
                setScreenTimeLimit(minutes: minutes, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing minutes", details: nil))
            }

        case "blockApp":
            if let args = call.arguments as? [String: Any],
               let bundleId = args["bundleId"] as? String {
                blockApp(bundleId: bundleId, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing bundleId", details: nil))
            }

        case "unblockApp":
            if let args = call.arguments as? [String: Any],
               let bundleId = args["bundleId"] as? String {
                unblockApp(bundleId: bundleId, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing bundleId", details: nil))
            }

        case "setContentFilter":
            if let args = call.arguments as? [String: Any],
               let level = args["level"] as? String {
                setContentFilter(level: level, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing level", details: nil))
            }

        case "setBedtimeMode":
            if let args = call.arguments as? [String: Any] {
                setBedtimeMode(args: args, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
            }

        case "setWebFilter":
            if let args = call.arguments as? [String: Any] {
                setWebFilter(args: args, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
            }

        case "setLocationSharing":
            if let args = call.arguments as? [String: Any],
               let enabled = args["enabled"] as? Bool {
                locationSharingEnabled = enabled
                result(["success": true, "location_sharing": enabled])
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing enabled", details: nil))
            }

        case "getCurrentSettings":
            getCurrentSettings(result: result)

        case "getDeviceInfo":
            getDeviceInfo(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Authorization

    private func requestAuthorization(result: @escaping FlutterResult) {
        // In production, this would use FamilyControls framework (iOS 15+)
        // AuthorizationCenter.shared.requestAuthorization(for: .individual)
        // For now, return success as the controls work at app level
        result(["authorized": true, "platform": "ios"])
    }

    // MARK: - Screen Time

    private func setScreenTimeLimit(minutes: Int, result: @escaping FlutterResult) {
        screenTimeLimit = max(0, min(minutes, 1440)) // 0-24 hours

        // In production: DeviceActivityMonitor scheduling
        // let schedule = DeviceActivitySchedule(...)
        // let center = DeviceActivityCenter()
        // try center.startMonitoring(schedule)

        result(["success": true, "limit_minutes": screenTimeLimit])
    }

    // MARK: - App Blocking

    private func blockApp(bundleId: String, result: @escaping FlutterResult) {
        if !blockedApps.contains(bundleId) {
            blockedApps.append(bundleId)
        }

        // In production: ManagedSettingsStore to shield apps
        // let store = ManagedSettingsStore()
        // store.shield.applications = Set(blockedApps.map { ... })

        result(["success": true, "blocked_apps": blockedApps])
    }

    private func unblockApp(bundleId: String, result: @escaping FlutterResult) {
        blockedApps.removeAll { $0 == bundleId }
        result(["success": true, "blocked_apps": blockedApps])
    }

    // MARK: - Content Filter

    private func setContentFilter(level: String, result: @escaping FlutterResult) {
        contentFilterLevel = level

        // In production: NEFilterManager for content filtering
        // NEFilterManager.shared().loadFromPreferences { ... }

        result(["success": true, "level": contentFilterLevel])
    }

    // MARK: - Bedtime

    private func setBedtimeMode(args: [String: Any], result: @escaping FlutterResult) {
        bedtimeEnabled = args["enabled"] as? Bool ?? false
        bedtimeStart = args["start"] as? String ?? "21:00"
        bedtimeEnd = args["end"] as? String ?? "07:00"

        // In production: DeviceActivitySchedule for bedtime
        // Schedule would restrict device during bedtime hours

        result([
            "success": true,
            "enabled": bedtimeEnabled,
            "start": bedtimeStart,
            "end": bedtimeEnd
        ])
    }

    // MARK: - Web Filter

    private func setWebFilter(args: [String: Any], result: @escaping FlutterResult) {
        webFilterEnabled = args["enabled"] as? Bool ?? false
        if let sites = args["blockedSites"] as? [String] {
            blockedWebsites = sites
        }

        result([
            "success": true,
            "enabled": webFilterEnabled,
            "blocked_count": blockedWebsites.count
        ])
    }

    // MARK: - Settings

    private func getCurrentSettings(result: @escaping FlutterResult) {
        result([
            "screenTimeLimit": screenTimeLimit,
            "usedScreenTime": usedScreenTime,
            "contentFilter": contentFilterLevel,
            "bedtimeEnabled": bedtimeEnabled,
            "bedtimeStart": bedtimeStart,
            "bedtimeEnd": bedtimeEnd,
            "blockedApps": blockedApps,
            "webFilterEnabled": webFilterEnabled,
            "blockedWebsites": blockedWebsites,
            "locationSharing": locationSharingEnabled
        ])
    }

    // MARK: - Device Info

    private func getDeviceInfo(result: @escaping FlutterResult) {
        let device = UIDevice.current

        result([
            "name": device.name,
            "system_name": device.systemName,
            "system_version": device.systemVersion,
            "model": device.model,
            "is_ipad": device.userInterfaceIdiom == .pad,
            "battery_level": device.batteryLevel,
            "battery_state": batteryStateString(device.batteryState)
        ])
    }

    private func batteryStateString(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging: return "charging"
        case .full: return "full"
        case .unplugged: return "discharging"
        default: return "unknown"
        }
    }
}
