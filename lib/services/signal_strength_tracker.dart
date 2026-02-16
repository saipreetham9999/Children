import 'dart:async';
import 'package:flutter/foundation.dart';

/// WSignalStrengthTracker — Monitors connection quality
/// Tracks both HTTP latency and Bluetooth RSSI
class WSignalStrengthTracker extends ChangeNotifier {
  // HTTP metrics
  int _httpLatencyMs = 0;  // Milliseconds (lower is better)
  double _httpSuccessRate = 100.0;  // Percentage (0-100)
  int _httpFailureCount = 0;
  int _httpSuccessCount = 0;

  // Bluetooth metrics
  int _bluetoothRssi = -100;  // RSSI (-100 to 0, higher is better)
  int _bluetoothDeviceCount = 0;
  bool _isBluetoothConnected = false;

  // Overall signal
  int _overallSignal = 100;  // 0-100
  String _preferredTransport = 'http';  // Which to prefer

  // History
  final List<int> _latencyHistory = [];
  final List<double> _signalHistory = [];
  static const int maxHistory = 60;  // Keep 60 samples

  // Callbacks
  Function(String transport)? onTransportChange;  // When switch between HTTP/BT
  Function(int signal)? onSignalChange;

  /// Current HTTP latency (ms)
  int get httpLatencyMs => _httpLatencyMs;

  /// Current HTTP success rate (%)
  double get httpSuccessRate => _httpSuccessRate;

  /// Current Bluetooth RSSI (-100 to 0)
  int get bluetoothRssi => _bluetoothRssi;

  /// Is Bluetooth connected
  bool get isBluetoothConnected => _isBluetoothConnected;

  /// Nearby Bluetooth devices
  int get bluetoothDeviceCount => _bluetoothDeviceCount;

  /// Overall signal strength (0-100)
  int get overallSignal => _overallSignal;

  /// Preferred transport method
  String get preferredTransport => _preferredTransport;

  /// Get signal indicator emoji
  String get signalIndicator {
    if (overallSignal >= 80) return '📶📶📶 Strong';
    if (overallSignal >= 50) return '📶📶 Medium';
    if (overallSignal >= 20) return '📶 Weak';
    return '❌ No signal';
  }

  /// Get transport emoji
  String get transportEmoji {
    return _preferredTransport == 'bluetooth' ? '📡' : '☁️';
  }

  /// Initialize tracker
  void initialize() {
    print('[SignalTracker] Initialized');
  }

  /// Record HTTP response time
  void recordHttpResponse({
    required int latencyMs,
    required bool success,
  }) {
    _httpLatencyMs = latencyMs;

    if (success) {
      _httpSuccessCount++;
    } else {
      _httpFailureCount++;
    }

    // Update success rate
    final total = _httpSuccessCount + _httpFailureCount;
    _httpSuccessRate = (_httpSuccessCount / total) * 100;

    // Convert latency to signal (lower latency = higher signal)
    // 0ms = 100, 500ms = 50, 1000ms+ = 0
    int signalFromLatency = 100 - ((latencyMs / 10).clamp(0, 100)).round();

    print('[SignalTracker] HTTP: ${latencyMs}ms, Success: $_httpSuccessRate%, Signal: $signalFromLatency%');

    _updateOverallSignal();
  }

  /// Record Bluetooth RSSI
  void recordBluetoothSignal({
    required int rssi,
    required int deviceCount,
  }) {
    _bluetoothRssi = rssi;
    _bluetoothDeviceCount = deviceCount;
    _isBluetoothConnected = rssi > -100;

    // Convert RSSI to signal (0-100)
    // RSSI: -30 to -100
    // Signal: 100 to 0
    int signalFromRssi = ((rssi + 100) * 100 / 70).clamp(0, 100).round();

    print('[SignalTracker] Bluetooth: RSSI=$rssi, Devices=$deviceCount, Signal: $signalFromRssi%');

    _updateOverallSignal();
  }

  /// Should prefer Bluetooth over HTTP?
  bool shouldPreferBluetooth() {
    // Prefer Bluetooth if:
    // 1. Connected and has good signal (RSSI > -70)
    // 2. HTTP is slow or failing (latency > 500ms OR success rate < 50%)
    if (!_isBluetoothConnected) return false;
    if (_bluetoothRssi <= -80) return false;  // Very weak signal

    final httpSignal = 100 - ((_httpLatencyMs / 10).clamp(0, 100)).round();
    final btSignal = ((_bluetoothRssi + 100) * 100 / 70).clamp(0, 100).round();

    // Bluetooth wins if it's significantly better
    return btSignal > httpSignal + 20;
  }

  /// Update overall signal and notify listeners
  void _updateOverallSignal() {
    final previousTransport = _preferredTransport;

    // Calculate overall signal (weighted average)
    int httpSignal = 100 - ((_httpLatencyMs / 10).clamp(0, 100)).round();
    httpSignal = (httpSignal * _httpSuccessRate / 100).round();

    int btSignal =
        _isBluetoothConnected ? ((_bluetoothRssi + 100) * 100 / 70).clamp(0, 100).round() : 0;

    // Determine which to use
    if (shouldPreferBluetooth()) {
      _overallSignal = btSignal;
      _preferredTransport = 'bluetooth';
    } else {
      _overallSignal = httpSignal.clamp(0, 100);
      _preferredTransport = 'http';
    }

    // Record history
    _signalHistory.add(_overallSignal.toDouble());
    if (_signalHistory.length > maxHistory) {
      _signalHistory.removeAt(0);
    }
    _latencyHistory.add(_httpLatencyMs);
    if (_latencyHistory.length > maxHistory) {
      _latencyHistory.removeAt(0);
    }

    // Notify if transport changed
    if (previousTransport != _preferredTransport) {
      print('[SignalTracker] ⚡ Switched to ${_preferredTransport.toUpperCase()}');
      onTransportChange?.call(_preferredTransport);
    }

    onSignalChange?.call(_overallSignal);
    notifyListeners();
  }

  /// Get stats
  Map<String, dynamic> getStats() {
    return {
      'overall_signal': _overallSignal,
      'preferred_transport': _preferredTransport,
      'http': {
        'latency_ms': _httpLatencyMs,
        'success_rate': _httpSuccessRate,
        'failures': _httpFailureCount,
        'successes': _httpSuccessCount,
      },
      'bluetooth': {
        'rssi': _bluetoothRssi,
        'is_connected': _isBluetoothConnected,
        'device_count': _bluetoothDeviceCount,
      },
      'history': {
        'signal_samples': _signalHistory.length,
        'avg_signal': _signalHistory.isEmpty
            ? 0
            : (_signalHistory.reduce((a, b) => a + b) / _signalHistory.length).round(),
        'avg_latency_ms': _latencyHistory.isEmpty
            ? 0
            : (_latencyHistory.reduce((a, b) => a + b) / _latencyHistory.length).round(),
      },
    };
  }

  /// Reset stats
  void resetStats() {
    _httpLatencyMs = 0;
    _httpSuccessRate = 100.0;
    _httpFailureCount = 0;
    _httpSuccessCount = 0;
    _bluetoothRssi = -100;
    _bluetoothDeviceCount = 0;
    _isBluetoothConnected = false;
    _signalHistory.clear();
    _latencyHistory.clear();
    _updateOverallSignal();
  }

  /// Get signal as emoji bars (like WhatsApp/Signal)
  String get signalBars {
    if (_overallSignal >= 80) return '▓▓▓▓';
    if (_overallSignal >= 60) return '▓▓▓░';
    if (_overallSignal >= 40) return '▓▓░░';
    if (_overallSignal >= 20) return '▓░░░';
    return '░░░░';
  }
}
