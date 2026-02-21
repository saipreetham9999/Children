import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// BLE Mesh Service — ShaRogai Multi-Hop Mesh Network
///
/// Every ShaRogai app acts as BOTH a BLE peripheral (advertises) AND
/// a BLE central (scans). Devices form a mesh so children far from Brain
/// can relay text chat through nearby children.
///
/// Architecture:
///   Child10 ──BLE──> Child5 ──BLE──> Child1 ──WiFi──> Brain
///
/// BLE 5 Long Range (Coded PHY) used when available: ~200m per hop
/// ─────────────────────────────────────────────────────────────────────────────

// ShaRogai BLE service UUID — all nodes advertise this
const String kShaRogaiServiceUuid = '0000FE01-0000-1000-8000-00805F9B34FB';
// Characteristic for mesh messages (read/write/notify)
const String kMeshMessageCharUuid = '0000FE02-0000-1000-8000-00805F9B34FB';
// Characteristic for routing info (read/notify)
const String kMeshRoutingCharUuid = '0000FE03-0000-1000-8000-00805F9B34FB';

/// Connection type to Brain
enum BrainConnectionType { direct, relay, none }

/// A discovered mesh peer
class MeshPeer {
  final String deviceId; // BLE device ID
  final String deviceName; // ShaRogai device name
  final int rssi; // Signal strength
  final int hopsToBrain; // How many hops this peer is from Brain (0 = direct)
  final bool isBridge; // Has direct WiFi to Brain
  final DateTime lastSeen;
  BluetoothDevice? bleDevice; // flutter_blue_plus device handle
  BluetoothCharacteristic? messageChar; // For sending messages
  BluetoothCharacteristic? routingChar; // For routing updates
  bool isConnected;

  MeshPeer({
    required this.deviceId,
    required this.deviceName,
    required this.rssi,
    this.hopsToBrain = 99,
    this.isBridge = false,
    DateTime? lastSeen,
    this.bleDevice,
    this.messageChar,
    this.routingChar,
    this.isConnected = false,
  }) : lastSeen = lastSeen ?? DateTime.now();

  /// Signal quality 0-100
  int get signalPercent => ((rssi + 100) * 100 / 70).clamp(0, 100).round();

  /// Signal bars display
  String get signalBars {
    final p = signalPercent;
    if (p >= 75) return '▓▓▓▓';
    if (p >= 50) return '▓▓▓░';
    if (p >= 25) return '▓▓░░';
    return '▓░░░';
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'device_name': deviceName,
        'rssi': rssi,
        'signal_percent': signalPercent,
        'hops_to_brain': hopsToBrain,
        'is_bridge': isBridge,
        'is_connected': isConnected,
        'last_seen': lastSeen.toIso8601String(),
      };
}

/// A mesh message envelope — wraps chat text for multi-hop delivery
class MeshMessage {
  final String id;
  final String fromDevice;
  final String toDevice; // 'brain' or 'all' or specific device name
  final String type; // 'chat', 'relay_register', 'relay_heartbeat', 'relay_response', 'routing_update'
  final String payload; // JSON string content
  final int ttl; // Time-to-live: max hops remaining
  final DateTime timestamp;
  final List<String> path; // Devices this message has passed through

  MeshMessage({
    String? id,
    required this.fromDevice,
    this.toDevice = 'brain',
    required this.type,
    required this.payload,
    this.ttl = 10,
    DateTime? timestamp,
    List<String>? path,
  })  : id = id ?? '${DateTime.now().millisecondsSinceEpoch}_${fromDevice.hashCode}',
        timestamp = timestamp ?? DateTime.now(),
        path = path ?? [];

  /// Serialize for BLE transmission
  String serialize() => jsonEncode({
        'id': id,
        'from': fromDevice,
        'to': toDevice,
        'type': type,
        'payload': payload,
        'ttl': ttl,
        'ts': timestamp.millisecondsSinceEpoch,
        'path': path,
      });

  /// Deserialize from BLE data
  static MeshMessage? deserialize(String data) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      return MeshMessage(
        id: json['id'] as String?,
        fromDevice: json['from'] as String? ?? 'unknown',
        toDevice: json['to'] as String? ?? 'brain',
        type: json['type'] as String? ?? 'chat',
        payload: json['payload'] as String? ?? '',
        ttl: json['ttl'] as int? ?? 10,
        timestamp: json['ts'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['ts'] as int)
            : null,
        path: (json['path'] as List?)?.cast<String>() ?? [],
      );
    } catch (e) {
      print('[Mesh] Failed to deserialize: $e');
      return null;
    }
  }

  /// Create a copy with decremented TTL and updated path
  MeshMessage forwarded(String byDevice) => MeshMessage(
        id: id,
        fromDevice: fromDevice,
        toDevice: toDevice,
        type: type,
        payload: payload,
        ttl: ttl - 1,
        timestamp: timestamp,
        path: [...path, byDevice],
      );

  /// Size in bytes
  int get sizeBytes => serialize().length;
}

/// ─────────────────────────────────────────────────────────────────────────────
/// WBleMeshService — The main mesh network service
/// ─────────────────────────────────────────────────────────────────────────────
class WBleMeshService extends ChangeNotifier {
  // Identity
  String _myDeviceName = '';
  bool _isBridge = false; // Do I have direct WiFi to Brain?
  int _myHopsToBrain = 99;

  // Peers
  final Map<String, MeshPeer> _peers = {};
  MeshPeer? _bestRelay; // Best peer to route through

  // Message tracking (avoid duplicates)
  final Set<String> _seenMessageIds = {};
  static const int _maxSeenIds = 500;

  // BLE state
  bool _isScanning = false;
  bool _isAdvertising = false;
  bool _isInitialized = false;
  StreamSubscription? _scanSubscription;
  Timer? _scanTimer;
  Timer? _routingTimer;

  // Callbacks
  Function(MeshMessage message)? onMessageReceived; // Chat message arrived
  Function(MeshMessage message)? onRelayRequest; // Registration/heartbeat to forward
  Function(List<MeshPeer> peers)? onPeersChanged;

  // Getters
  String get myDeviceName => _myDeviceName;
  bool get isBridge => _isBridge;
  int get myHopsToBrain => _myHopsToBrain;
  bool get isInitialized => _isInitialized;
  bool get isScanning => _isScanning;
  Map<String, MeshPeer> get peers => Map.unmodifiable(_peers);
  MeshPeer? get bestRelay => _bestRelay;
  int get peerCount => _peers.length;
  int get connectedPeerCount => _peers.values.where((p) => p.isConnected).length;

  /// Connected peers sorted by signal strength
  List<MeshPeer> get connectedPeers {
    final list = _peers.values.where((p) => p.isConnected).toList();
    list.sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  /// All discovered peers sorted by hops then signal
  List<MeshPeer> get discoveredPeers {
    final list = _peers.values.toList();
    list.sort((a, b) {
      final hopCmp = a.hopsToBrain.compareTo(b.hopsToBrain);
      if (hopCmp != 0) return hopCmp;
      return b.rssi.compareTo(a.rssi); // Higher RSSI = better
    });
    return list;
  }

  /// My connection type
  BrainConnectionType get connectionType {
    if (_isBridge) return BrainConnectionType.direct;
    if (_bestRelay != null) return BrainConnectionType.relay;
    return BrainConnectionType.none;
  }

  /// Path to Brain as string
  String get pathToBrain {
    if (_isBridge) return '$_myDeviceName → Brain (direct)';
    if (_bestRelay != null) {
      return '$_myDeviceName → ${_bestRelay!.deviceName} → Brain (${_myHopsToBrain} hops)';
    }
    return 'No path to Brain';
  }

  // ── Initialize ──────────────────────────────────────────────────────────

  /// Initialize the mesh service
  Future<void> initialize({
    required String deviceName,
    required bool hasBrainWifi,
  }) async {
    _myDeviceName = deviceName;
    _isBridge = hasBrainWifi;
    _myHopsToBrain = hasBrainWifi ? 0 : 99;

    print('[Mesh] Initializing: $_myDeviceName (bridge: $_isBridge)');

    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) {
        print('[Mesh] BLE not supported on this device');
        return;
      }

      // Start scanning for peers
      await startScanning();

      // Periodic re-scan every 30 seconds
      _scanTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!_isScanning) startScanning();
      });

      // Broadcast routing updates every 15 seconds
      _routingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _broadcastRoutingUpdate();
      });

      _isInitialized = true;
      print('[Mesh] Initialized');
      notifyListeners();
    } catch (e) {
      print('[Mesh] Init error: $e');
    }
  }

  // ── Scanning (Central role) ─────────────────────────────────────────────

  /// Scan for nearby ShaRogai nodes
  Future<void> startScanning() async {
    if (_isScanning) return;

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      print('[Mesh] Bluetooth is off');
      return;
    }

    print('[Mesh] Scanning for ShaRogai nodes...');
    _isScanning = true;
    notifyListeners();

    try {
      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
        for (final result in results) {
          _handleScanResult(result);
        }
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        withServices: [Guid(kShaRogaiServiceUuid)],
      );
    } catch (e) {
      print('[Mesh] Scan error: $e');
    }

    _isScanning = false;
    notifyListeners();

    // Clean stale peers (not seen in 60s)
    _cleanStalePeers();
  }

  /// Stop scanning
  Future<void> stopScanning() async {
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _isScanning = false;
  }

  /// Handle a scan result
  void _handleScanResult(ScanResult result) {
    final device = result.device;
    final name = device.platformName.isNotEmpty
        ? device.platformName
        : device.remoteId.str;
    final rssi = result.rssi;

    // Parse advertising data for mesh info
    int hopsToBrain = 99;
    bool peerIsBridge = false;
    String peerDeviceName = name;

    // Try to read mesh info from manufacturer data or service data
    final serviceData = result.advertisementData.serviceData;
    for (final entry in serviceData.entries) {
      try {
        final data = utf8.decode(entry.value);
        final info = jsonDecode(data) as Map<String, dynamic>;
        hopsToBrain = info['hops'] as int? ?? 99;
        peerIsBridge = info['bridge'] as bool? ?? false;
        peerDeviceName = info['name'] as String? ?? name;
      } catch (_) {}
    }

    // Also check local name from advertisement
    final localName = result.advertisementData.advName;
    if (localName.startsWith('SRG:')) {
      // Format: SRG:DeviceName:Hops:Bridge
      final parts = localName.split(':');
      if (parts.length >= 4) {
        peerDeviceName = parts[1];
        hopsToBrain = int.tryParse(parts[2]) ?? 99;
        peerIsBridge = parts[3] == '1';
      }
    }

    final peer = MeshPeer(
      deviceId: device.remoteId.str,
      deviceName: peerDeviceName,
      rssi: rssi,
      hopsToBrain: hopsToBrain,
      isBridge: peerIsBridge,
      bleDevice: device,
      isConnected: _peers[device.remoteId.str]?.isConnected ?? false,
      messageChar: _peers[device.remoteId.str]?.messageChar,
      routingChar: _peers[device.remoteId.str]?.routingChar,
    );

    _peers[device.remoteId.str] = peer;

    // Update best relay
    _updateBestRelay();

    print('[Mesh] Found: ${peer.deviceName} '
        '(RSSI: $rssi, Hops: ${peer.hopsToBrain}, Bridge: ${peer.isBridge})');

    notifyListeners();
    onPeersChanged?.call(discoveredPeers);
  }

  /// Remove peers not seen in 60 seconds
  void _cleanStalePeers() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 60));
    _peers.removeWhere((_, peer) =>
        !peer.isConnected && peer.lastSeen.isBefore(cutoff));
  }

  // ── Connection Management ───────────────────────────────────────────────

  /// Connect to a specific peer for message relay
  Future<bool> connectToPeer(String deviceId) async {
    final peer = _peers[deviceId];
    if (peer == null || peer.bleDevice == null) {
      print('[Mesh] Peer not found: $deviceId');
      return false;
    }

    if (peer.isConnected) {
      print('[Mesh] Already connected to ${peer.deviceName}');
      return true;
    }

    try {
      print('[Mesh] Connecting to ${peer.deviceName}...');

      await peer.bleDevice!.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );

      // Request BLE 5 Long Range PHY for maximum distance
      try {
        await peer.bleDevice!.requestMtu(512);
      } catch (_) {
        print('[Mesh] MTU request failed (non-fatal)');
      }

      // Discover services
      final services = await peer.bleDevice!.discoverServices();

      for (final service in services) {
        if (service.uuid.toString().toUpperCase() ==
            kShaRogaiServiceUuid.toUpperCase()) {
          for (final char in service.characteristics) {
            final charUuid = char.uuid.toString().toUpperCase();
            if (charUuid == kMeshMessageCharUuid.toUpperCase()) {
              peer.messageChar = char;
              // Subscribe to notifications for incoming messages
              await char.setNotifyValue(true);
              char.onValueReceived.listen((value) {
                _handleIncomingData(utf8.decode(value), peer.deviceName);
              });
            } else if (charUuid == kMeshRoutingCharUuid.toUpperCase()) {
              peer.routingChar = char;
              await char.setNotifyValue(true);
              char.onValueReceived.listen((value) {
                _handleRoutingUpdate(utf8.decode(value));
              });
            }
          }
        }
      }

      // Listen for disconnection
      peer.bleDevice!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          print('[Mesh] Disconnected from ${peer.deviceName}');
          _peers[deviceId] = MeshPeer(
            deviceId: peer.deviceId,
            deviceName: peer.deviceName,
            rssi: peer.rssi,
            hopsToBrain: peer.hopsToBrain,
            isBridge: peer.isBridge,
            bleDevice: peer.bleDevice,
            isConnected: false,
          );
          _updateBestRelay();
          notifyListeners();
        }
      });

      _peers[deviceId] = MeshPeer(
        deviceId: peer.deviceId,
        deviceName: peer.deviceName,
        rssi: peer.rssi,
        hopsToBrain: peer.hopsToBrain,
        isBridge: peer.isBridge,
        bleDevice: peer.bleDevice,
        messageChar: peer.messageChar,
        routingChar: peer.routingChar,
        isConnected: true,
      );

      _updateBestRelay();
      notifyListeners();

      print('[Mesh] Connected to ${peer.deviceName}');
      return true;
    } catch (e) {
      print('[Mesh] Connection failed to ${peer.deviceName}: $e');
      return false;
    }
  }

  /// Connect to best available relay
  Future<bool> connectToBestRelay() async {
    final candidates = discoveredPeers
        .where((p) => !p.isConnected && p.hopsToBrain < 99)
        .toList();

    if (candidates.isEmpty) {
      print('[Mesh] No relay candidates found');
      return false;
    }

    // Try connecting to the best candidate (fewest hops, strongest signal)
    for (final candidate in candidates) {
      if (await connectToPeer(candidate.deviceId)) {
        return true;
      }
    }
    return false;
  }

  /// Disconnect from a peer
  Future<void> disconnectPeer(String deviceId) async {
    final peer = _peers[deviceId];
    if (peer?.bleDevice == null) return;

    try {
      await peer!.bleDevice!.disconnect();
    } catch (e) {
      print('[Mesh] Disconnect error: $e');
    }
  }

  // ── Message Sending ─────────────────────────────────────────────────────

  /// Send a chat message through the mesh
  Future<bool> sendChatMessage(String text, {String to = 'all'}) async {
    final message = MeshMessage(
      fromDevice: _myDeviceName,
      toDevice: to,
      type: 'chat',
      payload: jsonEncode({'text': text}),
      path: [_myDeviceName],
    );

    return await sendMessage(message);
  }

  /// Send any mesh message (routes automatically)
  Future<bool> sendMessage(MeshMessage message) async {
    // Track this message ID
    _seenMessageIds.add(message.id);
    _trimSeenIds();

    if (_isBridge) {
      // I'm a bridge — this message needs to go to Brain via HTTP
      // The caller (chat_service or relay handler) will handle HTTP
      onRelayRequest?.call(message);
      return true;
    }

    // Route through best relay
    if (_bestRelay != null && _bestRelay!.isConnected) {
      return await _sendToPeer(_bestRelay!.deviceId, message);
    }

    // Try any connected peer
    for (final peer in connectedPeers) {
      if (await _sendToPeer(peer.deviceId, message)) {
        return true;
      }
    }

    print('[Mesh] No route available for message');
    return false;
  }

  /// Send message to a specific connected peer
  Future<bool> _sendToPeer(String deviceId, MeshMessage message) async {
    final peer = _peers[deviceId];
    if (peer == null || !peer.isConnected || peer.messageChar == null) {
      return false;
    }

    try {
      final data = message.serialize();
      final bytes = utf8.encode(data);

      // BLE MTU is typically 512 bytes. If message is larger, chunk it.
      if (bytes.length <= 500) {
        await peer.messageChar!.write(bytes, withoutResponse: false);
      } else {
        // Chunk into 490-byte pieces with header
        final chunks = _chunkData(bytes, 490);
        for (int i = 0; i < chunks.length; i++) {
          final header = 'CHK:${message.id}:$i:${chunks.length}:'.codeUnits;
          final packet = Uint8List(header.length + chunks[i].length);
          packet.setAll(0, header);
          packet.setAll(header.length, chunks[i]);
          await peer.messageChar!.write(packet, withoutResponse: false);
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }

      print('[Mesh] Sent to ${peer.deviceName}: ${message.type} (${bytes.length}B)');
      return true;
    } catch (e) {
      print('[Mesh] Send failed to ${peer.deviceName}: $e');
      return false;
    }
  }

  /// Chunk data into pieces
  List<Uint8List> _chunkData(List<int> data, int chunkSize) {
    final chunks = <Uint8List>[];
    for (int i = 0; i < data.length; i += chunkSize) {
      final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
      chunks.add(Uint8List.fromList(data.sublist(i, end)));
    }
    return chunks;
  }

  // ── Message Receiving ───────────────────────────────────────────────────

  /// Handle incoming data from a connected peer
  void _handleIncomingData(String data, String fromPeer) {
    final message = MeshMessage.deserialize(data);
    if (message == null) return;

    // Duplicate check
    if (_seenMessageIds.contains(message.id)) {
      print('[Mesh] Duplicate message ${message.id}, ignoring');
      return;
    }
    _seenMessageIds.add(message.id);
    _trimSeenIds();

    print('[Mesh] Received ${message.type} from ${message.fromDevice} via $fromPeer');

    // If TTL exhausted, drop
    if (message.ttl <= 0) {
      print('[Mesh] TTL expired for ${message.id}');
      return;
    }

    // Handle based on type
    switch (message.type) {
      case 'chat':
        // Deliver to local chat
        onMessageReceived?.call(message);
        // If I'm a bridge or relay, forward toward Brain
        if (_isBridge) {
          onRelayRequest?.call(message);
        } else {
          // Forward to other connected peers (flood)
          _forwardMessage(message, excludePeer: fromPeer);
        }
        break;

      case 'relay_register':
      case 'relay_heartbeat':
        // Forward to Brain (if I'm bridge) or relay further
        if (_isBridge) {
          onRelayRequest?.call(message);
        } else {
          _forwardMessage(message, excludePeer: fromPeer);
        }
        break;

      case 'relay_response':
        // Response from Brain coming back to a device
        if (message.toDevice == _myDeviceName) {
          onMessageReceived?.call(message);
        } else {
          _forwardMessage(message, excludePeer: fromPeer);
        }
        break;

      case 'chat_broadcast':
        // Message from Brain broadcast to all children
        onMessageReceived?.call(message);
        // Forward to all other connected peers
        _forwardMessage(message, excludePeer: fromPeer);
        break;

      default:
        print('[Mesh] Unknown message type: ${message.type}');
    }
  }

  /// Forward a message to connected peers (except the one it came from)
  void _forwardMessage(MeshMessage message, {String? excludePeer}) {
    final forwarded = message.forwarded(_myDeviceName);
    if (forwarded.ttl <= 0) return;

    for (final peer in connectedPeers) {
      if (peer.deviceName == excludePeer) continue;
      if (message.path.contains(peer.deviceName)) continue; // Avoid loops
      _sendToPeer(peer.deviceId, forwarded);
    }
  }

  // ── Routing ─────────────────────────────────────────────────────────────

  /// Update best relay (peer with fewest hops to Brain)
  void _updateBestRelay() {
    if (_isBridge) {
      _myHopsToBrain = 0;
      _bestRelay = null;
      return;
    }

    MeshPeer? best;
    for (final peer in _peers.values) {
      if (peer.hopsToBrain >= 99) continue;
      if (best == null || peer.hopsToBrain < best.hopsToBrain) {
        best = peer;
      } else if (peer.hopsToBrain == best.hopsToBrain && peer.rssi > best.rssi) {
        best = peer;
      }
    }

    _bestRelay = best;
    _myHopsToBrain = best != null ? best.hopsToBrain + 1 : 99;

    if (best != null) {
      print('[Mesh] Best relay: ${best.deviceName} '
          '(${best.hopsToBrain} hops, RSSI: ${best.rssi})');
    }
  }

  /// Handle routing update from a peer
  void _handleRoutingUpdate(String data) {
    try {
      final info = jsonDecode(data) as Map<String, dynamic>;
      final peerName = info['name'] as String?;
      final hops = info['hops'] as int? ?? 99;
      final bridge = info['bridge'] as bool? ?? false;

      // Update the peer's routing info
      for (final peer in _peers.values) {
        if (peer.deviceName == peerName) {
          _peers[peer.deviceId] = MeshPeer(
            deviceId: peer.deviceId,
            deviceName: peer.deviceName,
            rssi: peer.rssi,
            hopsToBrain: hops,
            isBridge: bridge,
            bleDevice: peer.bleDevice,
            messageChar: peer.messageChar,
            routingChar: peer.routingChar,
            isConnected: peer.isConnected,
          );
          break;
        }
      }

      _updateBestRelay();
      notifyListeners();
    } catch (e) {
      print('[Mesh] Routing update parse error: $e');
    }
  }

  /// Broadcast my routing info to all connected peers
  void _broadcastRoutingUpdate() {
    final info = jsonEncode({
      'name': _myDeviceName,
      'hops': _myHopsToBrain,
      'bridge': _isBridge,
      'peers': connectedPeerCount,
    });

    for (final peer in connectedPeers) {
      if (peer.routingChar != null) {
        try {
          peer.routingChar!.write(utf8.encode(info), withoutResponse: true);
        } catch (_) {}
      }
    }
  }

  /// Mark this device as a bridge (has WiFi to Brain)
  void setBridge(bool value) {
    _isBridge = value;
    _myHopsToBrain = value ? 0 : (_bestRelay != null ? _bestRelay!.hopsToBrain + 1 : 99);
    notifyListeners();
    _broadcastRoutingUpdate();
  }

  // ── Relay Registration ──────────────────────────────────────────────────

  /// Send a registration request through the mesh (for devices without WiFi)
  Future<bool> sendRelayRegistration(Map<String, dynamic> deviceInfo) async {
    final message = MeshMessage(
      fromDevice: _myDeviceName,
      toDevice: 'brain',
      type: 'relay_register',
      payload: jsonEncode(deviceInfo),
      path: [_myDeviceName],
    );

    return await sendMessage(message);
  }

  /// Send a heartbeat through the mesh
  Future<bool> sendRelayHeartbeat() async {
    final message = MeshMessage(
      fromDevice: _myDeviceName,
      toDevice: 'brain',
      type: 'relay_heartbeat',
      payload: jsonEncode({'device_name': _myDeviceName}),
      path: [_myDeviceName],
    );

    return await sendMessage(message);
  }

  // ── Utilities ───────────────────────────────────────────────────────────

  void _trimSeenIds() {
    if (_seenMessageIds.length > _maxSeenIds) {
      final excess = _seenMessageIds.length - _maxSeenIds;
      _seenMessageIds.removeAll(_seenMessageIds.take(excess).toList());
    }
  }

  /// Get mesh stats
  Map<String, dynamic> getStats() => {
        'device_name': _myDeviceName,
        'is_bridge': _isBridge,
        'hops_to_brain': _myHopsToBrain,
        'connection_type': connectionType.name,
        'path_to_brain': pathToBrain,
        'total_peers': peerCount,
        'connected_peers': connectedPeerCount,
        'best_relay': _bestRelay?.deviceName,
        'peers': _peers.values.map((p) => p.toJson()).toList(),
      };

  @override
  void dispose() {
    _scanTimer?.cancel();
    _routingTimer?.cancel();
    _scanSubscription?.cancel();
    stopScanning();
    // Disconnect all peers
    for (final peer in _peers.values) {
      peer.bleDevice?.disconnect();
    }
    super.dispose();
  }
}
