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

  /// GET /api/status — Get Brain status
  Future<Map<String, dynamic>> getStatus() async {
    try {
      final response = await http.get(Uri.parse('$brainUrl/api/status')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Status failed: ${response.statusCode}');
    } catch (e) {
      rethrow;
    }
  }

  /// POST /api/connect — Register device
  Future<Map<String, dynamic>> connect(WDeviceModel device) async {
    try {
      final response = await http.post(
        Uri.parse('$brainUrl/api/connect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(device.toJson()),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Connect failed: ${response.statusCode}');
    } catch (e) {
      rethrow;
    }
  }

  /// POST /api/heartbeat — Send heartbeat
  Future<void> sendHeartbeat() async {
    try {
      await http.post(
        Uri.parse('$brainUrl/api/heartbeat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'device_name': deviceName}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  /// GET /api/events — Poll for commands (e.g., 'capture_extra')
  Future<List<WAlertModel>> getEvents() async {
    try {
      final response = await http.get(
        Uri.parse('$brainUrl/api/events?device_name=$deviceName'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['events'] as List?)
                ?.map((e) => WAlertModel.fromJson(e as Map<String, dynamic>))
                .toList() ?? [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// POST /api/report — Send frame
  Future<void> sendFrame(List<int> frameBytes, {Map<String, dynamic>? context}) async {
    try {
      final response = await http.post(
        Uri.parse('$brainUrl/api/report'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_name': deviceName,
          'type': 'frame',
          'data': base64Encode(frameBytes),
          'context': context ?? {'source': 'background'},
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 15));
      
      print('[Brain] Frame report status: ${response.statusCode}');
    } catch (e) {
      print('[Brain] Frame report error: $e');
    }
  }
}
