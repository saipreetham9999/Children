import 'dart:async';
import 'package:flutter/foundation.dart';

/// DevicePolicy — A rule that controls device behavior
class DevicePolicy {
  final String id;
  final String name;
  final String type; // 'screen_time', 'app_block', 'bedtime', 'content_filter', 'location', 'web_filter'
  final bool enabled;
  final Map<String, dynamic> config;
  final List<String> targetDevices; // empty = all devices
  final DateTime createdAt;

  DevicePolicy({
    required this.id,
    required this.name,
    required this.type,
    this.enabled = true,
    this.config = const {},
    this.targetDevices = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'enabled': enabled,
        'config': config,
        'target_devices': targetDevices,
        'created_at': createdAt.toIso8601String(),
      };

  factory DevicePolicy.fromJson(Map<String, dynamic> json) {
    return DevicePolicy(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? '',
      enabled: json['enabled'] ?? true,
      config: json['config'] != null
          ? Map<String, dynamic>.from(json['config'])
          : {},
      targetDevices: json['target_devices'] != null
          ? List<String>.from(json['target_devices'])
          : [],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  /// Check if policy applies to a device
  bool appliesTo(String deviceName) {
    return targetDevices.isEmpty || targetDevices.contains(deviceName);
  }
}

/// PolicyViolation — Record of a policy being violated
class PolicyViolation {
  final String policyId;
  final String policyName;
  final String deviceName;
  final String description;
  final DateTime timestamp;
  final String severity; // 'info', 'warning', 'critical'

  PolicyViolation({
    required this.policyId,
    required this.policyName,
    required this.deviceName,
    required this.description,
    this.severity = 'warning',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'policy_id': policyId,
        'policy_name': policyName,
        'device_name': deviceName,
        'description': description,
        'severity': severity,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// WDevicePolicyService — Manages and enforces device policies across all children
class WDevicePolicyService extends ChangeNotifier {
  final List<DevicePolicy> _policies = [];
  final List<PolicyViolation> _violations = [];
  Timer? _enforcementTimer;
  bool _isEnforcing = false;

  // Callbacks for enforcement actions
  Function(String deviceName, String action, Map<String, dynamic> params)?
      onEnforceAction;
  Function(PolicyViolation violation)? onViolation;

  // Getters
  List<DevicePolicy> get policies => List.unmodifiable(_policies);
  List<DevicePolicy> get activePolicies =>
      _policies.where((p) => p.enabled).toList();
  List<PolicyViolation> get violations => List.unmodifiable(_violations);
  int get policyCount => _policies.length;
  int get violationCount => _violations.length;
  bool get isEnforcing => _isEnforcing;

  /// Initialize with default policies
  void initialize() {
    print('[DevicePolicy] Initializing...');

    // Add default policies
    addPolicy(DevicePolicy(
      id: 'default_screen_time',
      name: 'Daily Screen Time Limit',
      type: 'screen_time',
      config: {'limit_minutes': 120, 'warning_at_minutes': 100},
    ));

    addPolicy(DevicePolicy(
      id: 'default_bedtime',
      name: 'Bedtime Schedule',
      type: 'bedtime',
      config: {'start': '21:00', 'end': '07:00', 'allow_calls': true},
    ));

    addPolicy(DevicePolicy(
      id: 'default_content',
      name: 'Content Filter',
      type: 'content_filter',
      config: {'level': 'moderate', 'block_explicit': true},
    ));

    addPolicy(DevicePolicy(
      id: 'default_web',
      name: 'Web Safety',
      type: 'web_filter',
      enabled: true,
      config: {
        'block_adult': true,
        'block_gambling': true,
        'block_social_media': false,
        'custom_blocked': <String>[],
      },
    ));

    // Start enforcement loop
    startEnforcement();

    print('[DevicePolicy] Initialized with ${_policies.length} policies');
  }

  /// Add a policy
  void addPolicy(DevicePolicy policy) {
    // Remove existing policy with same ID
    _policies.removeWhere((p) => p.id == policy.id);
    _policies.add(policy);
    print('[DevicePolicy] Added: ${policy.name} (${policy.type})');
    notifyListeners();
  }

  /// Remove a policy
  void removePolicy(String policyId) {
    _policies.removeWhere((p) => p.id == policyId);
    print('[DevicePolicy] Removed policy: $policyId');
    notifyListeners();
  }

  /// Enable/disable a policy
  void togglePolicy(String policyId, bool enabled) {
    final index = _policies.indexWhere((p) => p.id == policyId);
    if (index >= 0) {
      final old = _policies[index];
      _policies[index] = DevicePolicy(
        id: old.id,
        name: old.name,
        type: old.type,
        enabled: enabled,
        config: old.config,
        targetDevices: old.targetDevices,
        createdAt: old.createdAt,
      );
      print('[DevicePolicy] ${old.name}: ${enabled ? "enabled" : "disabled"}');
      notifyListeners();
    }
  }

  /// Update policy config
  void updatePolicyConfig(String policyId, Map<String, dynamic> newConfig) {
    final index = _policies.indexWhere((p) => p.id == policyId);
    if (index >= 0) {
      final old = _policies[index];
      _policies[index] = DevicePolicy(
        id: old.id,
        name: old.name,
        type: old.type,
        enabled: old.enabled,
        config: newConfig,
        targetDevices: old.targetDevices,
        createdAt: old.createdAt,
      );
      notifyListeners();
    }
  }

  /// Get policies for a specific device
  List<DevicePolicy> getPoliciesForDevice(String deviceName) {
    return activePolicies.where((p) => p.appliesTo(deviceName)).toList();
  }

  /// Get policies by type
  List<DevicePolicy> getPoliciesByType(String type) {
    return _policies.where((p) => p.type == type).toList();
  }

  /// Start enforcement loop
  void startEnforcement() {
    if (_isEnforcing) return;
    _isEnforcing = true;

    _enforcementTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _enforceAllPolicies(),
    );

    print('[DevicePolicy] Enforcement started (30s interval)');
    notifyListeners();
  }

  /// Stop enforcement
  void stopEnforcement() {
    _isEnforcing = false;
    _enforcementTimer?.cancel();
    print('[DevicePolicy] Enforcement stopped');
    notifyListeners();
  }

  /// Check a device against all applicable policies
  /// Returns list of violations
  List<PolicyViolation> checkDevice({
    required String deviceName,
    required int screenTimeMinutes,
    required Map<String, int> appUsage,
    String? currentApp,
  }) {
    final deviceViolations = <PolicyViolation>[];

    for (var policy in getPoliciesForDevice(deviceName)) {
      switch (policy.type) {
        case 'screen_time':
          final limit = policy.config['limit_minutes'] as int? ?? 120;
          final warningAt = policy.config['warning_at_minutes'] as int? ?? 100;

          if (screenTimeMinutes >= limit) {
            deviceViolations.add(PolicyViolation(
              policyId: policy.id,
              policyName: policy.name,
              deviceName: deviceName,
              description:
                  'Screen time limit exceeded: ${screenTimeMinutes}m / ${limit}m',
              severity: 'critical',
            ));
          } else if (screenTimeMinutes >= warningAt) {
            deviceViolations.add(PolicyViolation(
              policyId: policy.id,
              policyName: policy.name,
              deviceName: deviceName,
              description:
                  'Approaching screen time limit: ${screenTimeMinutes}m / ${limit}m',
              severity: 'warning',
            ));
          }
          break;

        case 'bedtime':
          final start = policy.config['start'] as String? ?? '21:00';
          final end = policy.config['end'] as String? ?? '07:00';
          if (_isInTimeRange(start, end)) {
            deviceViolations.add(PolicyViolation(
              policyId: policy.id,
              policyName: policy.name,
              deviceName: deviceName,
              description: 'Device active during bedtime ($start - $end)',
              severity: 'warning',
            ));
          }
          break;

        case 'app_block':
          final blockedApps =
              (policy.config['blocked_apps'] as List?)?.cast<String>() ?? [];
          if (currentApp != null && blockedApps.contains(currentApp)) {
            deviceViolations.add(PolicyViolation(
              policyId: policy.id,
              policyName: policy.name,
              deviceName: deviceName,
              description: 'Blocked app in use: $currentApp',
              severity: 'critical',
            ));
          }
          break;

        default:
          break;
      }
    }

    // Record violations
    for (var v in deviceViolations) {
      _violations.add(v);
      onViolation?.call(v);
    }

    // Trim violation history (keep last 500)
    if (_violations.length > 500) {
      _violations.removeRange(0, _violations.length - 500);
    }

    if (deviceViolations.isNotEmpty) {
      notifyListeners();
    }

    return deviceViolations;
  }

  /// Enforce all policies (called by timer)
  void _enforceAllPolicies() {
    // This is called periodically; actual enforcement happens
    // when checkDevice is called with real data from each child
    print('[DevicePolicy] Enforcement check (${activePolicies.length} active policies)');
  }

  /// Create a quick screen time policy for a device
  void setScreenTimeForDevice(String deviceName, int limitMinutes) {
    addPolicy(DevicePolicy(
      id: 'screen_time_$deviceName',
      name: 'Screen Time: $deviceName',
      type: 'screen_time',
      config: {
        'limit_minutes': limitMinutes,
        'warning_at_minutes': (limitMinutes * 0.8).round(),
      },
      targetDevices: [deviceName],
    ));
  }

  /// Create a quick app block policy for a device
  void blockAppsForDevice(String deviceName, List<String> appBundleIds) {
    addPolicy(DevicePolicy(
      id: 'app_block_$deviceName',
      name: 'App Block: $deviceName',
      type: 'app_block',
      config: {'blocked_apps': appBundleIds},
      targetDevices: [deviceName],
    ));
  }

  /// Create bedtime policy for a device
  void setBedtimeForDevice(
      String deviceName, String start, String end) {
    addPolicy(DevicePolicy(
      id: 'bedtime_$deviceName',
      name: 'Bedtime: $deviceName',
      type: 'bedtime',
      config: {'start': start, 'end': end, 'allow_calls': true},
      targetDevices: [deviceName],
    ));
  }

  /// Get violations for a device
  List<PolicyViolation> getViolationsForDevice(String deviceName) {
    return _violations.where((v) => v.deviceName == deviceName).toList();
  }

  /// Get recent violations (last hour)
  List<PolicyViolation> get recentViolations {
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    return _violations.where((v) => v.timestamp.isAfter(cutoff)).toList();
  }

  /// Clear violations
  void clearViolations() {
    _violations.clear();
    notifyListeners();
  }

  /// Check if current time is within range (handles overnight)
  bool _isInTimeRange(String start, String end) {
    final now = DateTime.now();
    final startParts = start.split(':');
    final endParts = end.split(':');

    final currentMinutes = now.hour * 60 + now.minute;
    final startMinutes =
        int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

    if (startMinutes > endMinutes) {
      // Overnight (e.g., 21:00 - 07:00)
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }
    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  }

  /// Get all stats
  Map<String, dynamic> getStats() {
    return {
      'total_policies': _policies.length,
      'active_policies': activePolicies.length,
      'total_violations': _violations.length,
      'recent_violations': recentViolations.length,
      'is_enforcing': _isEnforcing,
      'policies': _policies.map((p) => p.toJson()).toList(),
    };
  }

  @override
  void dispose() {
    stopEnforcement();
    super.dispose();
  }
}
