import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';
import 'ble_mesh_service.dart';
import 'chat_service.dart';
import 'signal_strength_tracker.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// WMeshChatTransport — Bridges BLE Mesh ↔ Chat Service
///
/// This is the GLUE between the mesh network and the chat UI.
/// It does NOT duplicate any logic from:
///   - WChatService (message storage, sync timer, display)
///   - WBluetoothConnectivity (general BLE device scanning)
///   - WSignalStrengthTracker (signal quality monitoring)
///   - WBrainService (HTTP API calls)
///
/// It ONLY handles:
///   1. Outgoing: WChatMessage → MeshMessage → BLE mesh send
///   2. Incoming: BLE mesh receive → MeshMessage → WChatMessage → ChatService
///   3. Bridge relay: mesh messages → HTTP POST to Brain (if this device is bridge)
///   4. Brain poll: HTTP GET from Brain → broadcast to mesh (if bridge)
/// ─────────────────────────────────────────────────────────────────────────────
class WMeshChatTransport extends ChangeNotifier {
  final WBleMeshService _meshService;
  final WChatService _chatService;
  final WSignalStrengthTracker _signalTracker;

  String _brainUrl = '';
  String _deviceName = '';
  bool _isRunning = false;
  Timer? _brainPollTimer;
  Timer? _heartbeatTimer;

  // Stats
  int _messagesSentViaMesh = 0;
  int _messagesReceivedViaMesh = 0;
  int _messagesRelayedToBrain = 0;
  int _messagesRelayedFromBrain = 0;

  // Getters
  bool get isRunning => _isRunning;
  int get messagesSentViaMesh => _messagesSentViaMesh;
  int get messagesReceivedViaMesh => _messagesReceivedViaMesh;
  int get messagesRelayedToBrain => _messagesRelayedToBrain;
  int get messagesRelayedFromBrain => _messagesRelayedFromBrain;
  String get deviceName => _deviceName;

  WMeshChatTransport({
    required WBleMeshService meshService,
    required WChatService chatService,
    required WSignalStrengthTracker signalTracker,
  })  : _meshService = meshService,
        _chatService = chatService,
        _signalTracker = signalTracker;

  /// Initialize the transport layer
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _brainUrl = prefs.getString('brain_url') ?? '';
    _deviceName = prefs.getString('device_name') ?? 'Unknown';

    // Determine if this device is a bridge (has WiFi to Brain)
    final isBridge = _brainUrl.isNotEmpty && await _canReachBrain();

    // Initialize mesh service (does NOT duplicate WBluetoothConnectivity scanning
    // — mesh scans for ShaRogai-specific service UUID only)
    await _meshService.initialize(
      deviceName: _deviceName,
      hasBrainWifi: isBridge,
    );

    // Wire up mesh callbacks
    _meshService.onMessageReceived = _handleMeshMessageReceived;
    _meshService.onRelayRequest = _handleRelayRequest;

    // If bridge, poll Brain for chat messages to broadcast
    if (isBridge) {
      _brainPollTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _pollBrainForChat(),
      );
    }

    // Heartbeat through mesh (for non-bridge devices)
    if (!isBridge) {
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _meshService.sendRelayHeartbeat(),
      );
    }

    // Feed mesh peer signal data into signal tracker
    _meshService.onPeersChanged = (peers) {
      if (peers.isNotEmpty) {
        final bestRssi = peers.first.rssi;
        _signalTracker.recordBluetoothSignal(
          rssi: bestRssi,
          deviceCount: peers.length,
        );
      }
    };

    _isRunning = true;
    notifyListeners();

    print('[MeshChat] Initialized (bridge: $isBridge, device: $_deviceName)');
  }

  // ── Sending (ChatService → Mesh) ────────────────────────────────────────

  /// Send a chat message through the mesh network.
  /// Called from the chat screen instead of direct HTTP when mesh is active.
  Future<bool> sendChat(String text) async {
    if (!_isRunning) return false;

    // Create the mesh message
    final sent = await _meshService.sendChatMessage(text);

    if (sent) {
      _messagesSentViaMesh++;

      // Add to local chat so sender sees it immediately.
      // Use 'You' as sender to match chat_screen.dart isOwn check (sender == 'You').
      // The mesh message itself carries _deviceName for other devices.
      await _chatService.sendMessage(
        'You',
        text,
        transportType: 'mesh',
        signalStrength: _meshService.bestRelay?.signalPercent ?? 50,
      );

      notifyListeners();
    }

    return sent;
  }

  // ── Receiving (Mesh → ChatService) ──────────────────────────────────────

  /// Handle incoming mesh message — convert to WChatMessage and add to chat
  void _handleMeshMessageReceived(MeshMessage message) {
    if (message.type == 'chat' || message.type == 'chat_broadcast') {
      try {
        final payload = jsonDecode(message.payload) as Map<String, dynamic>;
        final text = payload['text'] as String? ?? '';
        if (text.isEmpty) return;

        // Don't add our own messages again (we already added them on send)
        if (message.fromDevice == _deviceName) return;

        final chatMessage = WChatMessage(
          id: message.id,
          sender: message.fromDevice,
          text: text,
          signalStrength: _estimateSignalFromHops(message.path.length),
          transportType: 'mesh',
          isSynced: false,
        );

        _chatService.addMessage(chatMessage);
        _messagesReceivedViaMesh++;
        notifyListeners();

        print('[MeshChat] Received: "${chatMessage.text}" '
            'from ${chatMessage.sender} (${message.path.length} hops)');
      } catch (e) {
        print('[MeshChat] Parse error: $e');
      }
    }

    if (message.type == 'relay_response') {
      // Brain sent a response back to this device
      try {
        final payload = jsonDecode(message.payload) as Map<String, dynamic>;
        final text = payload['text'] as String? ?? '';
        if (text.isNotEmpty) {
          final chatMessage = WChatMessage(
            id: message.id,
            sender: 'Brain',
            text: text,
            transportType: 'mesh',
            isSynced: true,
          );
          _chatService.addMessage(chatMessage);
        }
      } catch (_) {}
    }
  }

  // ── Bridge Relay (Mesh → Brain HTTP) ────────────────────────────────────

  /// Handle relay request: forward mesh message to Brain via HTTP.
  /// ONLY runs on bridge devices (those with WiFi to Brain).
  /// Does NOT use WBrainService to avoid coupling — uses direct HTTP.
  void _handleRelayRequest(MeshMessage message) async {
    if (_brainUrl.isEmpty) return;

    try {
      if (message.type == 'chat') {
        // Forward chat to Brain's chat endpoint
        final response = await http.post(
          Uri.parse('$_brainUrl/api/chat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'from_device': message.fromDevice,
            'text': jsonDecode(message.payload)['text'],
            'via_mesh': true,
            'hops': message.path.length,
            'path': message.path,
          }),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          _messagesRelayedToBrain++;
          print('[MeshChat] Relayed chat from ${message.fromDevice} to Brain');

          // If Brain has a response, send it back through mesh
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          if (body.containsKey('response')) {
            final responseMsg = MeshMessage(
              fromDevice: 'Brain',
              toDevice: message.fromDevice,
              type: 'relay_response',
              payload: jsonEncode({'text': body['response']}),
            );
            _meshService.sendMessage(responseMsg);
          }
        }
      } else if (message.type == 'relay_register') {
        // Forward registration to Brain
        await http.post(
          Uri.parse('$_brainUrl/api/connect'),
          headers: {'Content-Type': 'application/json'},
          body: message.payload,
        ).timeout(const Duration(seconds: 10));

        print('[MeshChat] Relayed registration from ${message.fromDevice}');
      } else if (message.type == 'relay_heartbeat') {
        // Forward heartbeat to Brain
        await http.post(
          Uri.parse('$_brainUrl/api/heartbeat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'device_name': message.fromDevice,
            'via_mesh': true,
          }),
        ).timeout(const Duration(seconds: 5));
      }
    } catch (e) {
      print('[MeshChat] Relay to Brain failed: $e');
    }
  }

  // ── Brain Polling (Brain HTTP → Mesh broadcast) ─────────────────────────

  /// Poll Brain for new chat messages and broadcast to mesh.
  /// ONLY runs on bridge devices.
  Future<void> _pollBrainForChat() async {
    if (_brainUrl.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('$_brainUrl/api/chat/messages'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final messages = body['messages'] as List? ?? [];

        for (final msg in messages) {
          final text = msg['text'] as String? ?? '';
          final from = msg['from'] as String? ?? 'Brain';
          if (text.isEmpty) continue;

          // Broadcast to mesh
          final meshMsg = MeshMessage(
            fromDevice: from,
            toDevice: 'all',
            type: 'chat_broadcast',
            payload: jsonEncode({'text': text}),
            path: [_deviceName],
          );
          await _meshService.sendMessage(meshMsg);
          _messagesRelayedFromBrain++;

          // Also add to local chat on this bridge device
          _chatService.addMessage(WChatMessage(
            id: meshMsg.id,
            sender: from,
            text: text,
            transportType: 'mesh',
            isSynced: true,
          ));
        }

        if (messages.isNotEmpty) notifyListeners();
      }
    } catch (e) {
      // Brain unreachable — don't spam logs, just skip
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  /// Check if Brain is reachable via HTTP
  Future<bool> _canReachBrain() async {
    if (_brainUrl.isEmpty) return false;
    try {
      final response = await http.get(
        Uri.parse('$_brainUrl/api/status'),
      ).timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Estimate signal strength from hop count
  int _estimateSignalFromHops(int hops) {
    // 1 hop = ~80%, 2 hops = ~65%, 3+ = ~50%, 5+ = ~30%
    if (hops <= 1) return 80;
    if (hops <= 2) return 65;
    if (hops <= 3) return 50;
    if (hops <= 5) return 30;
    return 15;
  }

  /// Get transport stats
  Map<String, dynamic> getStats() => {
        'is_running': _isRunning,
        'device_name': _deviceName,
        'brain_url': _brainUrl,
        'is_bridge': _meshService.isBridge,
        'connection_type': _meshService.connectionType.name,
        'path_to_brain': _meshService.pathToBrain,
        'hops_to_brain': _meshService.myHopsToBrain,
        'mesh_peers': _meshService.peerCount,
        'connected_peers': _meshService.connectedPeerCount,
        'sent_via_mesh': _messagesSentViaMesh,
        'received_via_mesh': _messagesReceivedViaMesh,
        'relayed_to_brain': _messagesRelayedToBrain,
        'relayed_from_brain': _messagesRelayedFromBrain,
      };

  @override
  void dispose() {
    _brainPollTimer?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }
}
