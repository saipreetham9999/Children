import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:battery_plus/battery_plus.dart';

/// ChildDeviceInfo — Snapshot of a child device's state
class ChildDeviceInfo {
  final String deviceName;
  final String osType; // 'ios', 'android', 'unknown'
  final String osVersion;
  final String model;
  final int batteryLevel;
  final String batteryState; // 'charging', 'discharging', 'full', 'unknown'
  final bool isOnline;
  final DateTime lastSeen;
  final int screenTimeUsedMinutes;
  final double storageUsedPercent;
  final String networkType; // 'wifi', 'cellular', 'bluetooth', 'none'
  final Map<String, int> appUsage; // app -> minutes

  ChildDeviceInfo({
    required this.deviceName,
    required this.osType,
    required this.osVersion,
    required this.model,
    required this.batteryLevel,
    this.batteryState = 'unknown',
    this.isOnline = true,
    DateTime? lastSeen,
    this.screenTimeUsedMinutes = 0,
    this.storageUsedPercent = 0,
    this.networkType = 'wifi',
    this.appUsage = const {},
  }) : lastSeen = lastSeen ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'device_name': deviceName,
        'os_type': osType,
        'os_version': osVersion,
        'model': model,
        'battery_level': batteryLevel,
        'battery_state': batteryState,
        'is_online': isOnline,
        'last_seen': lastSeen.toIso8601String(),
        'screen_time_used_minutes': screenTimeUsedMinutes,
        'storage_used_percent': storageUsedPercent,
        'network_type': networkType,
        'app_usage': appUsage,
      };

  factory ChildDeviceInfo.fromJson(Map<String, dynamic> json) {
    return ChildDeviceInfo(
      deviceName: json['device_name'] ?? 'Unknown',
      osType: json['os_type'] ?? 'unknown',
      osVersion: json['os_version'] ?? '',
      model: json['model'] ?? '',
      batteryLevel: json['battery_level'] ?? 0,
      batteryState: json['battery_state'] ?? 'unknown',
      isOnline: json['is_online'] ?? false,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'])
          : null,
      screenTimeUsedMinutes: json['screen_time_used_minutes'] ?? 0,
      storageUsedPercent:
          (json['storage_used_percent'] as num?)?.toDouble() ?? 0,
      networkType: json['network_type'] ?? 'unknown',
      appUsage: json['app_usage'] != null
          ? Map<String, int>.from(json['app_usage'])
          : {},
    );
  }

  /// Battery indicator
  String get batteryIndicator {
    if (batteryLevel >= 80) return 'Full';
    if (batteryLevel >= 50) return 'Good';
    if (batteryLevel >= 20) return 'Low';
    return 'Critical';
  }
}

/// WChildOSMonitor — Cross-platform child device monitoring
/// Tracks app usage, screen time, battery, location across all connected children
class WChildOSMonitor extends ChangeNotifier {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final Battery _battery = Battery();

  // This device's info
  ChildDeviceInfo? _thisDevice;
  String _thisDeviceName = 'Unknown';

  // All connected child devices (reported via Brain)
  final Map<String, ChildDeviceInfo> _childDevices = {};

  // Monitoring state
  bool _isMonitoring = false;
  Timer? _monitorTimer;
  Timer? _screenTimeTimer;
  int _sessionScreenTimeMinutes = 0;
  DateTime? _sessionStart;

  // App tracking (this device)
  final Map<String, int> _localAppUsage = {};
  String _currentApp = 'com.sharogai.worker';

  // Location tracking
  double? _lastLatitude;
  double? _lastLongitude;
  DateTime? _lastLocationUpdate;

  // Getters
  ChildDeviceInfo? get thisDevice => _thisDevice;
  String get thisDeviceName => _thisDeviceName;
  Map<String, ChildDeviceInfo> get childDevices =>
      Map.unmodifiable(_childDevices);
  int get connectedChildCount => _childDevices.length;
  bool get isMonitoring => _isMonitoring;
  int get sessionScreenTimeMinutes => _sessionScreenTimeMinutes;
  Map<String, int> get localAppUsage => Map.unmodifiable(_localAppUsage);
  double? get lastLatitude => _lastLatitude;
  double? get lastLongitude => _lastLongitude;

  /// Initialize monitor with device name
  Future<void> initialize(String deviceName) async {
    _thisDeviceName = deviceName;
    _sessionStart = DateTime.now();

    print('[ChildOSMonitor] Initializing for device: $deviceName');

    // Collect this device's info
    await _collectThisDeviceInfo();

    // Start monitoring loop
    startMonitoring();

    print('[ChildOSMonitor] Initialized');
  }

  /// Collect info about this device
  Future<void> _collectThisDeviceInfo() async {
    try {
      String osType = 'unknown';
      String osVersion = '';
      String model = '';

      if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        osType = 'ios';
        osVersion = info.systemVersion;
        model = info.utsname.machine;
      } else if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        osType = 'android';
        osVersion = 'Android ${info.version.release}';
        model = '${info.manufacturer} ${info.model}';
      }

      final batteryLevel = await _battery.batteryLevel;
      final batteryState = await _battery.batteryState;

      _thisDevice = ChildDeviceInfo(
        deviceName: _thisDeviceName,
        osType: osType,
        osVersion: osVersion,
        model: model,
        batteryLevel: batteryLevel,
        batteryState: _batteryStateToString(batteryState),
        isOnline: true,
        screenTimeUsedMinutes: _sessionScreenTimeMinutes,
        appUsage: Map.from(_localAppUsage),
      );

      notifyListeners();
    } catch (e) {
      print('[ChildOSMonitor] Device info error: $e');
    }
  }

  /// Start monitoring loop (updates every 60 seconds)
  void startMonitoring() {
    if (_isMonitoring) return;
    _isMonitoring = true;

    // Update device info every 60 seconds
    _monitorTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _collectThisDeviceInfo(),
    );

    // Track screen time every minute
    _screenTimeTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) {
        _sessionScreenTimeMinutes++;
        // Track current app usage
        _localAppUsage[_currentApp] =
            (_localAppUsage[_currentApp] ?? 0) + 1;
        notifyListeners();
      },
    );

    // Listen to battery changes
    _battery.onBatteryStateChanged.listen((state) {
      if (_thisDevice != null) {
        _collectThisDeviceInfo();
      }
    });

    print('[ChildOSMonitor] Monitoring started');
    notifyListeners();
  }

  /// Stop monitoring
  void stopMonitoring() {
    _isMonitoring = false;
    _monitorTimer?.cancel();
    _screenTimeTimer?.cancel();
    print('[ChildOSMonitor] Monitoring stopped');
    notifyListeners();
  }

  /// Register a remote child device (called when Brain reports new device)
  void registerChildDevice(ChildDeviceInfo info) {
    _childDevices[info.deviceName] = info;
    print('[ChildOSMonitor] Registered child: ${info.deviceName} '
        '(${info.osType} ${info.osVersion})');
    notifyListeners();
  }

  /// Update a remote child device's info
  void updateChildDevice(String deviceName, ChildDeviceInfo info) {
    _childDevices[deviceName] = info;
    notifyListeners();
  }

  /// Remove a child device (disconnected)
  void removeChildDevice(String deviceName) {
    _childDevices.remove(deviceName);
    print('[ChildOSMonitor] Removed child: $deviceName');
    notifyListeners();
  }

  /// Mark child as offline
  void markChildOffline(String deviceName) {
    final existing = _childDevices[deviceName];
    if (existing != null) {
      _childDevices[deviceName] = ChildDeviceInfo(
        deviceName: existing.deviceName,
        osType: existing.osType,
        osVersion: existing.osVersion,
        model: existing.model,
        batteryLevel: existing.batteryLevel,
        batteryState: existing.batteryState,
        isOnline: false,
        lastSeen: existing.lastSeen,
        screenTimeUsedMinutes: existing.screenTimeUsedMinutes,
        appUsage: existing.appUsage,
      );
      notifyListeners();
    }
  }

  /// Record app switch on this device
  void recordAppSwitch(String newAppBundleId) {
    _currentApp = newAppBundleId;
    print('[ChildOSMonitor] App switch: $newAppBundleId');
  }

  /// Update location
  void updateLocation(double latitude, double longitude) {
    _lastLatitude = latitude;
    _lastLongitude = longitude;
    _lastLocationUpdate = DateTime.now();
    notifyListeners();
  }

  /// Get all online children
  List<ChildDeviceInfo> get onlineChildren =>
      _childDevices.values.where((d) => d.isOnline).toList();

  /// Get all offline children
  List<ChildDeviceInfo> get offlineChildren =>
      _childDevices.values.where((d) => !d.isOnline).toList();

  /// Get children with low battery (<20%)
  List<ChildDeviceInfo> get lowBatteryChildren =>
      _childDevices.values.where((d) => d.batteryLevel < 20).toList();

  /// Get children sorted by screen time (highest first)
  List<ChildDeviceInfo> get childrenByScreenTime {
    final list = _childDevices.values.toList();
    list.sort(
        (a, b) => b.screenTimeUsedMinutes.compareTo(a.screenTimeUsedMinutes));
    return list;
  }

  /// Get aggregate stats across all children
  Map<String, dynamic> getAggregateStats() {
    final allDevices = _childDevices.values.toList();
    if (allDevices.isEmpty) {
      return {
        'total_children': 0,
        'online': 0,
        'offline': 0,
      };
    }

    final totalScreenTime = allDevices.fold<int>(
        0, (sum, d) => sum + d.screenTimeUsedMinutes);
    final avgBattery = allDevices.fold<int>(
            0, (sum, d) => sum + d.batteryLevel) ~/
        allDevices.length;

    return {
      'total_children': allDevices.length,
      'online': onlineChildren.length,
      'offline': offlineChildren.length,
      'total_screen_time_minutes': totalScreenTime,
      'avg_battery': avgBattery,
      'low_battery_count': lowBatteryChildren.length,
      'os_distribution': _getOSDistribution(),
    };
  }

  Map<String, int> _getOSDistribution() {
    final dist = <String, int>{};
    for (var d in _childDevices.values) {
      dist[d.osType] = (dist[d.osType] ?? 0) + 1;
    }
    return dist;
  }

  /// Build report for Brain API
  Map<String, dynamic> buildReport() {
    return {
      'this_device': _thisDevice?.toJson(),
      'children': _childDevices.map((k, v) => MapEntry(k, v.toJson())),
      'aggregate': getAggregateStats(),
      'session': {
        'start': _sessionStart?.toIso8601String(),
        'screen_time_minutes': _sessionScreenTimeMinutes,
        'app_usage': _localAppUsage,
      },
      'location': _lastLatitude != null
          ? {
              'latitude': _lastLatitude,
              'longitude': _lastLongitude,
              'updated': _lastLocationUpdate?.toIso8601String(),
            }
          : null,
    };
  }

  String _batteryStateToString(BatteryState state) {
    switch (state) {
      case BatteryState.charging:
        return 'charging';
      case BatteryState.discharging:
        return 'discharging';
      case BatteryState.full:
        return 'full';
      default:
        return 'unknown';
    }
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
