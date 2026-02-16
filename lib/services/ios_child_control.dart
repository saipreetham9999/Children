import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// WiOSChildControl — iOS Screen Time, App Restrictions & Content Filtering
/// Uses platform channels to native iOS Family Controls / Screen Time API
class WiOSChildControl extends ChangeNotifier {
  static const platform = MethodChannel('com.sharogai.child/control');

  // State
  bool _isAuthorized = false;
  bool _screenTimeEnabled = false;
  int _dailyScreenTimeLimitMinutes = 120; // 2 hours default
  int _usedScreenTimeMinutes = 0;
  List<String> _blockedApps = [];
  List<String> _allowedApps = [];
  String _contentFilterLevel = 'moderate'; // 'off', 'moderate', 'strict'
  bool _bedtimeModeActive = false;
  String _bedtimeStart = '21:00';
  String _bedtimeEnd = '07:00';
  Map<String, int> _appUsageMinutes = {}; // app_id -> minutes used today
  bool _webFilterEnabled = false;
  List<String> _blockedWebsites = [];
  bool _locationSharingEnabled = false;

  // Getters
  bool get isAuthorized => _isAuthorized;
  bool get screenTimeEnabled => _screenTimeEnabled;
  int get dailyScreenTimeLimitMinutes => _dailyScreenTimeLimitMinutes;
  int get usedScreenTimeMinutes => _usedScreenTimeMinutes;
  int get remainingScreenTimeMinutes =>
      (_dailyScreenTimeLimitMinutes - _usedScreenTimeMinutes).clamp(0, 9999);
  double get screenTimeUsagePercent =>
      _dailyScreenTimeLimitMinutes > 0
          ? (_usedScreenTimeMinutes / _dailyScreenTimeLimitMinutes * 100)
              .clamp(0, 100)
          : 0;
  List<String> get blockedApps => List.unmodifiable(_blockedApps);
  List<String> get allowedApps => List.unmodifiable(_allowedApps);
  String get contentFilterLevel => _contentFilterLevel;
  bool get bedtimeModeActive => _bedtimeModeActive;
  String get bedtimeStart => _bedtimeStart;
  String get bedtimeEnd => _bedtimeEnd;
  Map<String, int> get appUsageMinutes => Map.unmodifiable(_appUsageMinutes);
  bool get webFilterEnabled => _webFilterEnabled;
  List<String> get blockedWebsites => List.unmodifiable(_blockedWebsites);
  bool get locationSharingEnabled => _locationSharingEnabled;
  bool get isScreenTimeLimitReached =>
      _usedScreenTimeMinutes >= _dailyScreenTimeLimitMinutes;

  /// Initialize child controls (iOS only via Family Controls framework)
  Future<bool> initialize() async {
    if (!Platform.isIOS) {
      print('[iOSChildControl] Not iOS, skipping native init');
      _isAuthorized = true; // Allow usage tracking on non-iOS
      notifyListeners();
      return true;
    }

    try {
      final result = await platform.invokeMethod<Map>('requestAuthorization');
      _isAuthorized = result?['authorized'] == true;
      print('[iOSChildControl] Authorization: $_isAuthorized');

      if (_isAuthorized) {
        await _loadCurrentSettings();
      }

      notifyListeners();
      return _isAuthorized;
    } catch (e) {
      print('[iOSChildControl] Init error: $e');
      // Fallback: allow in-app tracking even without native API
      _isAuthorized = true;
      notifyListeners();
      return true;
    }
  }

  /// Set daily screen time limit
  Future<void> setDailyScreenTimeLimit(int minutes) async {
    if (minutes < 0 || minutes > 1440) return; // 0-24 hours

    _dailyScreenTimeLimitMinutes = minutes;
    print('[iOSChildControl] Screen time limit: ${minutes}m');

    if (Platform.isIOS) {
      try {
        await platform.invokeMethod('setScreenTimeLimit', {
          'minutes': minutes,
        });
      } catch (e) {
        print('[iOSChildControl] Set limit error: $e');
      }
    }

    notifyListeners();
  }

  /// Record screen time usage (called periodically)
  void recordScreenTime(int minutes) {
    _usedScreenTimeMinutes += minutes;
    _screenTimeEnabled = true;

    if (isScreenTimeLimitReached) {
      print('[iOSChildControl] Screen time limit reached!');
    }

    notifyListeners();
  }

  /// Record app-specific usage
  void recordAppUsage(String appId, int minutes) {
    _appUsageMinutes[appId] = (_appUsageMinutes[appId] ?? 0) + minutes;
    notifyListeners();
  }

  /// Block an app by bundle ID
  Future<void> blockApp(String appBundleId) async {
    if (_blockedApps.contains(appBundleId)) return;

    _blockedApps.add(appBundleId);
    _allowedApps.remove(appBundleId);

    if (Platform.isIOS) {
      try {
        await platform.invokeMethod('blockApp', {'bundleId': appBundleId});
      } catch (e) {
        print('[iOSChildControl] Block app error: $e');
      }
    }

    print('[iOSChildControl] Blocked: $appBundleId');
    notifyListeners();
  }

  /// Unblock an app
  Future<void> unblockApp(String appBundleId) async {
    _blockedApps.remove(appBundleId);

    if (Platform.isIOS) {
      try {
        await platform.invokeMethod('unblockApp', {'bundleId': appBundleId});
      } catch (e) {
        print('[iOSChildControl] Unblock app error: $e');
      }
    }

    print('[iOSChildControl] Unblocked: $appBundleId');
    notifyListeners();
  }

  /// Add app to allowed list (whitelist mode)
  void addAllowedApp(String appBundleId) {
    if (!_allowedApps.contains(appBundleId)) {
      _allowedApps.add(appBundleId);
      _blockedApps.remove(appBundleId);
      notifyListeners();
    }
  }

  /// Set content filter level
  Future<void> setContentFilterLevel(String level) async {
    if (!['off', 'moderate', 'strict'].contains(level)) return;

    _contentFilterLevel = level;

    if (Platform.isIOS) {
      try {
        await platform.invokeMethod('setContentFilter', {'level': level});
      } catch (e) {
        print('[iOSChildControl] Set filter error: $e');
      }
    }

    print('[iOSChildControl] Content filter: $level');
    notifyListeners();
  }

  /// Enable/disable bedtime mode
  Future<void> setBedtimeMode({
    required bool enabled,
    String? start,
    String? end,
  }) async {
    _bedtimeModeActive = enabled;
    if (start != null) _bedtimeStart = start;
    if (end != null) _bedtimeEnd = end;

    if (Platform.isIOS) {
      try {
        await platform.invokeMethod('setBedtimeMode', {
          'enabled': enabled,
          'start': _bedtimeStart,
          'end': _bedtimeEnd,
        });
      } catch (e) {
        print('[iOSChildControl] Bedtime error: $e');
      }
    }

    print('[iOSChildControl] Bedtime: $enabled ($_bedtimeStart - $_bedtimeEnd)');
    notifyListeners();
  }

  /// Check if currently in bedtime hours
  bool isInBedtimeHours() {
    if (!_bedtimeModeActive) return false;

    final now = DateTime.now();
    final startParts = _bedtimeStart.split(':');
    final endParts = _bedtimeEnd.split(':');

    final startHour = int.parse(startParts[0]);
    final startMinute = int.parse(startParts[1]);
    final endHour = int.parse(endParts[0]);
    final endMinute = int.parse(endParts[1]);

    final currentMinutes = now.hour * 60 + now.minute;
    final startMinutes = startHour * 60 + startMinute;
    final endMinutes = endHour * 60 + endMinute;

    // Handle overnight bedtime (e.g., 21:00 - 07:00)
    if (startMinutes > endMinutes) {
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }
    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  }

  /// Enable/disable web content filtering
  Future<void> setWebFilter({
    required bool enabled,
    List<String>? blockedSites,
  }) async {
    _webFilterEnabled = enabled;
    if (blockedSites != null) _blockedWebsites = blockedSites;

    if (Platform.isIOS) {
      try {
        await platform.invokeMethod('setWebFilter', {
          'enabled': enabled,
          'blockedSites': _blockedWebsites,
        });
      } catch (e) {
        print('[iOSChildControl] Web filter error: $e');
      }
    }

    print('[iOSChildControl] Web filter: $enabled, blocked: ${_blockedWebsites.length} sites');
    notifyListeners();
  }

  /// Block a website
  void blockWebsite(String url) {
    if (!_blockedWebsites.contains(url)) {
      _blockedWebsites.add(url);
      notifyListeners();
    }
  }

  /// Unblock a website
  void unblockWebsite(String url) {
    _blockedWebsites.remove(url);
    notifyListeners();
  }

  /// Enable/disable location sharing
  Future<void> setLocationSharing(bool enabled) async {
    _locationSharingEnabled = enabled;

    if (Platform.isIOS) {
      try {
        await platform.invokeMethod('setLocationSharing', {
          'enabled': enabled,
        });
      } catch (e) {
        print('[iOSChildControl] Location sharing error: $e');
      }
    }

    notifyListeners();
  }

  /// Reset daily usage (call at midnight)
  void resetDailyUsage() {
    _usedScreenTimeMinutes = 0;
    _appUsageMinutes.clear();
    notifyListeners();
  }

  /// Load current settings from native side
  Future<void> _loadCurrentSettings() async {
    if (!Platform.isIOS) return;

    try {
      final settings = await platform.invokeMethod<Map>('getCurrentSettings');
      if (settings != null) {
        _dailyScreenTimeLimitMinutes =
            settings['screenTimeLimit'] as int? ?? 120;
        _contentFilterLevel =
            settings['contentFilter'] as String? ?? 'moderate';
        _bedtimeModeActive = settings['bedtimeEnabled'] as bool? ?? false;
        _bedtimeStart = settings['bedtimeStart'] as String? ?? '21:00';
        _bedtimeEnd = settings['bedtimeEnd'] as String? ?? '07:00';
        notifyListeners();
      }
    } catch (e) {
      print('[iOSChildControl] Load settings error: $e');
    }
  }

  /// Get formatted remaining time
  String get remainingTimeFormatted {
    final remaining = remainingScreenTimeMinutes;
    final hours = remaining ~/ 60;
    final mins = remaining % 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  /// Get usage status indicator
  String get usageStatusIndicator {
    final pct = screenTimeUsagePercent;
    if (pct >= 100) return 'LIMIT REACHED';
    if (pct >= 80) return 'Almost at limit';
    if (pct >= 50) return 'Half used';
    return 'Plenty left';
  }

  /// Get stats
  Map<String, dynamic> getStats() {
    return {
      'authorized': _isAuthorized,
      'screen_time': {
        'enabled': _screenTimeEnabled,
        'limit_minutes': _dailyScreenTimeLimitMinutes,
        'used_minutes': _usedScreenTimeMinutes,
        'remaining_minutes': remainingScreenTimeMinutes,
        'usage_percent': screenTimeUsagePercent,
        'limit_reached': isScreenTimeLimitReached,
      },
      'apps': {
        'blocked_count': _blockedApps.length,
        'allowed_count': _allowedApps.length,
        'blocked': _blockedApps,
        'usage': _appUsageMinutes,
      },
      'content_filter': _contentFilterLevel,
      'bedtime': {
        'active': _bedtimeModeActive,
        'start': _bedtimeStart,
        'end': _bedtimeEnd,
        'currently_in_bedtime': isInBedtimeHours(),
      },
      'web_filter': {
        'enabled': _webFilterEnabled,
        'blocked_sites': _blockedWebsites.length,
      },
      'location_sharing': _locationSharingEnabled,
    };
  }
}
