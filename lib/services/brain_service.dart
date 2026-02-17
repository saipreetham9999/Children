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

  /// POST /api/report — Send frame or audio to Brain
  Future<void> sendReport({
    required String type, // 'frame', 'audio', 'voice_text'
    required String data, // Base64 encoded content or text
    Map<String, dynamic>? context,
  }) async {
    try {
      final url = '$brainUrl/api/report';

      final payload = {
        'device_name': deviceName,
        'type': type,
        'data': data,
        'timestamp': DateTime.now().toIso8601String(),
        'context': context ?? {
          'source': 'auto_detection',
        }
      };

      print('[WBrain] Sending $type report...');
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        print('[WBrain] ✅ $type sent successfully');
      } else {
        print('[WBrain] ❌ $type failed: ${response.statusCode}');
      }
    } catch (e) {
      print('[WBrain] ❌ Report error ($type): $e');
    }
  }

  /// Compatibility wrapper for old sendFrame calls
  Future<void> sendFrame(List<int> frameBytes, {Map<String, dynamic>? context}) async {
    await sendReport(
      type: 'frame',
      data: base64Encode(frameBytes),
      context: context,
    );
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
