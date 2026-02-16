import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// WBluetoothConnectivity — Bluetooth device discovery and signal strength
class WBluetoothConnectivity extends ChangeNotifier {
  static final WBluetoothConnectivity _instance =
      WBluetoothConnectivity._internal();
  factory WBluetoothConnectivity() => _instance;
  WBluetoothConnectivity._internal();

  final Map<String, BluetoothDevice> _nearbyDevices = {};
  final Map<String, int> _signalStrengths = {};  // RSSI per device
  bool _isScanning = false;

  // Callbacks
  Function(String deviceName, int signalStrength)? onDeviceFound;
  Function(String deviceName)? onDeviceLost;
  Function(bool)? onBluetoothToggle;

  /// Get nearby devices
  Map<String, BluetoothDevice> get nearbyDevices => _nearbyDevices;

  /// Get signal strength map (RSSI: -100 to 0, where 0 is strongest)
  Map<String, int> get signalStrengths => _signalStrengths;

  /// Get signal strength as 0-100 scale
  Map<String, int> get signalStrengthPercent {
    final percent = <String, int>{};
    _signalStrengths.forEach((device, rssi) {
      // Convert RSSI (-100 to 0) to percentage (0 to 100)
      final percentage = ((rssi + 100) * 100 / 100).clamp(0, 100).round();
      percent[device] = percentage;
    });
    return percent;
  }

  /// Is Bluetooth enabled
  Future<bool> get isBluetoothEnabled async {
    return FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
  }

  /// Count of nearby devices
  int get nearbyDeviceCount => _nearbyDevices.length;

  /// Initialize Bluetooth
  Future<void> initialize() async {
    print('[BluetoothConnectivity] Initializing...');

    try {
      // Check if Bluetooth is supported
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) {
        print('[BluetoothConnectivity] ⚠️  Bluetooth not supported on this device');
        return;
      }

      // Listen to Bluetooth state
      FlutterBluePlus.adapterState.listen((state) {
        print('[BluetoothConnectivity] Bluetooth state: $state');
        onBluetoothToggle?.call(state == BluetoothAdapterState.on);
      });

      print('[BluetoothConnectivity] ✅ Initialized');
    } catch (e) {
      print('[BluetoothConnectivity] Init error: $e');
    }
  }

  /// Start scanning for nearby devices
  Future<void> startScanning({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_isScanning) {
      print('[BluetoothConnectivity] Already scanning');
      return;
    }

    final isOn = await isBluetoothEnabled;
    if (!isOn) {
      print('[BluetoothConnectivity] ⚠️  Bluetooth is off');
      return;
    }

    print('[BluetoothConnectivity] Starting BLE scan...');
    _isScanning = true;

    try {
      // Listen to scan results
      var subscription = FlutterBluePlus.onScanResults.listen((results) {
        for (ScanResult result in results) {
          final device = result.device;
          final rssi = result.rssi;
          final name = device.platformName.isNotEmpty ? device.platformName : device.remoteId.str;

          _nearbyDevices[name] = device;
          _signalStrengths[name] = rssi;

          print('[BluetoothConnectivity] Found: $name '
              '(RSSI: $rssi, Signal: ${signalStrengthPercent[name]}%)');

          onDeviceFound?.call(name, rssi);
          notifyListeners();
        }
      });

      // Start scan
      await FlutterBluePlus.startScan(timeout: timeout);

      // Stop scan after timeout and cancel subscription if needed
      Future.delayed(timeout, () {
        stopScanning();
        subscription.cancel();
      });
    } catch (e) {
      print('[BluetoothConnectivity] Scan error: $e');
      _isScanning = false;
    }
  }

  /// Stop scanning
  Future<void> stopScanning() async {
    if (!_isScanning) return;
    print('[BluetoothConnectivity] Stopping scan');
    await FlutterBluePlus.stopScan();
    _isScanning = false;
  }

  /// Connect to specific device
  Future<bool> connectToDevice(String deviceName) async {
    final device = _nearbyDevices[deviceName];
    if (device == null) {
      print('[BluetoothConnectivity] Device not found: $deviceName');
      return false;
    }

    try {
      print('[BluetoothConnectivity] Connecting to $deviceName...');
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));
      print('[BluetoothConnectivity] ✅ Connected to $deviceName');
      return true;
    } catch (e) {
      print('[BluetoothConnectivity] Connection error: $e');
      return false;
    }
  }

  /// Disconnect from device
  Future<void> disconnectDevice(String deviceName) async {
    final device = _nearbyDevices[deviceName];
    if (device == null) return;

    try {
      print('[BluetoothConnectivity] Disconnecting from $deviceName');
      await device.disconnect();
    } catch (e) {
      print('[BluetoothConnectivity] Disconnect error: $e');
    }
  }

  /// Get best signal device (for mesh routing)
  String? getBestSignalDevice() {
    if (_signalStrengths.isEmpty) return null;
    var best = _signalStrengths.entries.first;
    for (var entry in _signalStrengths.entries) {
      if (entry.value > best.value) {
        best = entry;
      }
    }
    return best.key;
  }

  /// Get devices sorted by signal strength
  List<MapEntry<String, int>> getDevicesBySignal() {
    return _signalStrengths.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Send data to device (requires gatt characteristic)
  Future<void> sendDataToDevice(String deviceName, List<int> data) async {
    final device = _nearbyDevices[deviceName];
    if (device == null) {
      print('[BluetoothConnectivity] Device not found: $deviceName');
      return;
    }

    try {
      // Discover services and write to characteristic
      print('[BluetoothConnectivity] Sending data to $deviceName...');
    } catch (e) {
      print('[BluetoothConnectivity] Send error: $e');
    }
  }

  /// Get Bluetooth stats
  Map<String, dynamic> getStats() {
    final devices = getDevicesBySignal();
    return {
      'is_bluetooth_on': null,  // Will be set by caller
      'nearby_devices': nearbyDeviceCount,
      'devices': devices.map((e) => {
            'name': e.key,
            'signal_strength': e.value,
            'signal_percent': signalStrengthPercent[e.key] ?? 0,
          }).toList(),
      'best_signal_device': getBestSignalDevice(),
    };
  }

  /// Cleanup
  @override
  void dispose() {
    stopScanning();
    for (var device in _nearbyDevices.values) {
      device.disconnect();
    }
    super.dispose();
    print('[BluetoothConnectivity] Disposed');
  }
}
