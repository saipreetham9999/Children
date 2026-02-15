import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
/// WAlertModel — Alert received from Brain
class WAlertModel {
  final String type; // 'alert', 'child_connected', 'child_disconnected'
  final String? message;
  final String? severity; // 'high', 'medium', 'low'
  final String? deviceName;
  final DateTime timestamp;

  WAlertModel({
    required this.type,
    this.message,
    this.severity,
    this.deviceName,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory WAlertModel.fromJson(Map<String, dynamic> json) {
    return WAlertModel(
      type: json['type'] ?? 'unknown',
      message: json['message'],
      severity: json['severity'],
      deviceName: json['device_name'],
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
    );
  }

  String get formattedTime {
    return DateFormat('HH:mm:ss').format(timestamp);
  }

  String get displayText {
    if (message != null) return message!;
    if (type == 'child_connected' && deviceName != null) {
      return '$deviceName connected';
    }
    if (type == 'child_disconnected' && deviceName != null) {
      return '$deviceName disconnected';
    }
    return type;
  }

  Color get severityColor {
    switch (severity?.toLowerCase()) {
      case 'high':
        return const Color(0xFFFF4444); // red
      case 'medium':
        return const Color(0xFFFFAA00); // orange
      case 'low':
        return const Color(0xFF44AA44); // green
      default:
        return const Color(0xFF2196F3); // blue
    }
  }

  @override
  String toString() => 'WAlert($type - $message at $formattedTime)';
}


