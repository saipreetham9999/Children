import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/device_model.dart';
import '../models/alert_model.dart';

/// WBrainService — Communication with Brain server
class WBrainService {
  late String brainUrl;
  late String deviceName;
  late int heartbeatIntervalSeconds;

  WBrainService({
    required this.brainUrl,
    required this.deviceName,
    this.heartbeatIntervalSeconds = 5,
  });

  /// POST /api/connect — Register device with Brain
  Future<Map<String, dynamic>> connect(WDeviceModel device) async {
    try {
      print('[WBrain] Connecting to $brainUrl/api/connect');
      final response = await http.post(
        Uri.parse('$brainUrl/api/connect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(device.toJson()),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('[WBrain] Connected: ${data['status']}');
        return data;
      } else {
        print('[WBrain] Connect failed: ${response.statusCode}');
        throw Exception('Connect failed: ${response.statusCode}');
      }
    } catch (e) {
      print('[WBrain] Connect error: $e');
      rethrow;
    }
  }

  /// GET /api/status — Get Brain status and connected children
  Future<Map<String, dynamic>> getStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$brainUrl/api/status'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Status failed: ${response.statusCode}');
      }
    } catch (e) {
      print('[WBrain] Status error: $e');
      rethrow;
    }
  }

  /// POST /api/heartbeat — Send heartbeat to stay alive
  Future<void> sendHeartbeat() async {
    try {
      final response = await http.post(
        Uri.parse('$brainUrl/api/heartbeat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'device_name': deviceName}),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        print('[WBrain] Heartbeat OK');
      } else {
        print('[WBrain] Heartbeat failed: ${response.statusCode}');
      }
    } catch (e) {
      print('[WBrain] Heartbeat error: $e');
    }
  }

  /// GET /api/events — Poll for pending alerts/messages
  Future<List<WAlertModel>> getEvents() async {
    try {
      final response = await http.get(
        Uri.parse('$brainUrl/api/events?device_name=$deviceName'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final events = (data['events'] as List?)
                ?.map((e) => WAlertModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        print('[WBrain] Got ${events.length} events');
        return events;
      } else {
        return [];
      }
    } catch (e) {
      print('[WBrain] Events error: $e');
      return [];
    }
  }

  /// POST /api/report — Send frame to Brain for AI processing
  Future<void> sendFrame(List<int> frameBytes, {String frameType = 'jpeg'}) async {
    try {
      print('[SendFrame] Starting... frame size: ${frameBytes.length} bytes');

      if (frameBytes.isEmpty) {
        print('[SendFrame] ERROR: Frame bytes empty!');
        return;
      }

      // Base64 encode
      print('[SendFrame] Encoding to base64...');
      final base64Frame = base64Encode(frameBytes);
      print('[SendFrame] Base64 encoded size: ${base64Frame.length} characters');

      // Build URL
      final url = '$brainUrl/api/report';
      print('[SendFrame] URL: $url');
      print('[SendFrame] Device: $deviceName');

      // Build payload
      final payload = {
        'device_name': deviceName,
        'type': 'frame',
        'frame_type': frameType,
        'data': base64Frame,
      };

      print('[SendFrame] Payload keys: ${payload.keys}');
      print('[SendFrame] Sending POST request...');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      print('[SendFrame] Response status: ${response.statusCode}');
      print('[SendFrame] Response body: ${response.body}');

      if (response.statusCode == 200) {
        print('[SendFrame] ✅ SUCCESS: Frame sent (${frameBytes.length} bytes)');
      } else {
        print('[SendFrame] ❌ FAILED: ${response.statusCode}');
        print('[SendFrame] Response: ${response.body}');
      }
    } catch (e) {
      print('[SendFrame] ❌ ERROR: $e');
      print('[SendFrame] ERROR Type: ${e.runtimeType}');
    }
  }

  /// POST /api/disconnect — Cleanly disconnect from Brain
  Future<void> disconnect() async {
    try {
      await http.post(
        Uri.parse('$brainUrl/api/disconnect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'device_name': deviceName}),
      ).timeout(const Duration(seconds: 5));
      print('[WBrain] Disconnected');
    } catch (e) {
      print('[WBrain] Disconnect error: $e');
    }
  }
}
